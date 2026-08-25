# Tasks: Tap package search and install (`m11-tap-search`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m11-tap-search/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `chain_strategy=pending`, `review_budget_lines=5000`, `strict_tdd=true`.
RDD disabled. **`size:exception` accepted by the maintainer on 2026-08-25** — see the Round 2 forecast.

> **This file has two rounds.** Round 1 (phases 0–7 below) **landed** on `feat/m11-tap-search` at
> **`dbc5233`** and is kept as **completed history**, boxes included. The 2026-08-25 maintainer scope
> change supersedes its surface decisions; the governing plan is **[Round 2 — scope change](#round-2--scope-change-2026-08-25-binding)**,
> at the bottom of this file. The **only** Review Workload Forecast guard block is Round 2's.

## Round 1 — landed at `dbc5233` (history)

Inputs: the four spec deltas **rev 2, gate-passed**
(`specs/{package-search,package-detail,tap-management}/spec.md` + `specs/README.md` — **19 new
scenarios**: 16 / 1 / 2, of which **15 `unit`** and **4 `unit-app`**), `design.md` (**DD-1…DD-13**,
whose Testing Strategy table is the RED map), `proposal.md`, `explore.md`. Engram mirrors: spec
`#7798`, design `#7797`, proposal `#7796`, decisions `#7795`.

Size note: this artifact exceeds the generic 530-word phase budget, on the house precedent at
`openspec/changes/archive/2026-08-23-m7-tap-trust/tasks.md:16`,
`2026-08-24-m9-per-package-trust/tasks.md:15` and `2026-08-24-m10-third-party-detail/tasks.md:13`.
Nothing is padded.

### Scenario map — round 1 (rev 2 specs; superseded by the Round 2 map)

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

### Pinned copy — round 1 (superseded by the Round 2 table; `From your taps` is **withdrawn**)

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

### Review Workload Forecast — round 1 (history; **superseded**, guard lines removed)

The four round-1 guard lines are **deleted on purpose**: exactly one guard block may exist in this
file, and it is Round 2's. Round 1 measured **4,404** authored lines on the branch at `dbc5233` —
inside the band below, and the base the Round 2 forecast builds on.

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

*(Round-1 guard lines removed — the governing block is in Round 2 below.)*

**Branch**: `feat/m11-tap-search`
(`^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)/[a-z0-9._-]+$` ✓).
**PR title (round 1, superseded)**: `feat(browse): find and install packages published by your taps`.

### Suggested Work Units — round 1 (landed at `dbc5233`)

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

*(Every box in phases 0–7 below is round-1 history at `dbc5233`. The live plan starts at
[Round 2](#round-2--scope-change-2026-08-25-binding).)*

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

- [x] 4.1 **Fixture (not a behaviour).** Build a resident tap inventory of realistic size — **several
      taps publishing ≈500 packages in total**, mixed formulae and casks, deterministic — alongside the
      **shipped PS6 catalog fixture**, reused as-is rather than re-created.
- [x] 4.2 **RED.** `theCombinedKeystrokeTurnStaysUnderTheCeiling`: **≥100** representative as-you-type
      queries of varying length run the **catalog query and the tap composition on the same turn**;
      the **p95** of that combined duration is **below 8 ms**. **RED because** `hits(…)` does not exist
      at authoring time. *(ps12)*
- [x] 4.3 **Explicitly not a re-run of shipped PS6**, which never touches the tap inventory: this row
      measures the combined turn and must not replace, relax or re-baseline PS6's own scenario.
- [x] 4.4 **The ceiling is not negotiable.** If p95 misses, the fix is the projection (allocation per
      keystroke, repeated normalisation, an O(n·m) scan) — **never** a larger ceiling, a smaller
      inventory, fewer queries or a p90. A miss that survives optimisation is a **design deviation to
      report**, not to absorb.
- [x] 4.5 Focused command green; commit WU3
      (`test(search): pin the combined catalog and tap keystroke turn under 8 ms`).

## Phase 5: WU4 — the Browse surface (ps13–ps16)

Runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`

> `cellar/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup`s (`project.pbxproj` :46, :51),
> so both new files join their targets with a **0-line `project.pbxproj` diff**.

- [x] 5.1 **RED.** New file `cellarTests/TapSearchCompositionTests.swift` ·
      `browseComposesTheTapSectionFromTheResidentStore`: `BrowseView.swift` contains a `taps` store
      property and builds `TapPackageSearch(` from it; `ContentView.swift` passes `taps: taps` at the
      `BrowseView(…)` call site (`:307-315`). **RED because** neither exists yet. *(ps13)*
- [x] 5.2 **RED.** `theTapSectionIsTitledAndPositionedLast`: `TapSearchSection.swift` contains the
      section title **byte-exact** — `From your taps` — and `BrowseView.swift` places that section
      **after** the catalog `ForEach` inside a single `List(selection:)`. *(ps13)*
- [x] 5.3 **RED.** `notInstalledTapRowsAreNotSelectable`: rows are tagged with `hit.routableID`, so a
      `nil` routable id yields no selectable tag; the not-installed and ambiguous cases are the same
      code path. *(ps13, ps14, DD-4)*
- [x] 5.4 **RED.** `theSurfaceCopyLivesInTheProjectionNotTheView`: the four pinned strings —
      `Also in the catalog. Homebrew installs the catalog package.`, `Installed.`,
      `Installed. Homebrew withholds its tap while this tap is untrusted.`, `Not installed.` — are
      present in `TapPackageSearch.swift` and **absent** from `TapSearchSection.swift`, which renders
      `hit.stateCopy` and `hit.collisionNote` instead. *(ps15, PS8's copy-ownership clause)*
- [x] 5.5 **RED.** `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge`: scanning **both**
      `TapSearchSection.swift` and the `BrowseView.swift` tap surface finds no `TrustGrantStore`, no
      `TrustGrantState`, no `TapProjection.trust(`, no `TapCommand`, no `"Untrusted"` and no `"Trust`
      literal; the install affordance is offered for **every** hit whatever the origin tap's trust
      state, through `MutationMenu` over
      `PackageEntry(installed: nil, catalog: nil, id: hit.mutationTarget)` — which renders exactly
      Install + Copy install command (`MutationMenu.swift:32-40`, via
      `InstalledFilterMode.swift:54`). *(ps15, PM10, TM12 gains no consumer)*
- [x] 5.6 **RED.** `theReceiptDetailIsReachedWithNoNewRoutingBranch`: `PackageDetailView.swift` has a
      **zero-line diff** — no new branch, no tap import, no `TapSearchHit` reference — and selection
      stays `PackageID?`, so an unambiguous installed hit lands on the m10 receipt-backed detail through
      the **existing** resolution order. *(ps14, DD-4)*
- [x] 5.7 **RED.** `neitherTapSearchFileReachesTheProcessLayer`: scanning **both** new/modified Browse
      files finds no brew-process reference, no `Process`, and no store refresh triggered by presenting
      the section; the composition takes only already-resident values, with no launcher dependency to
      inject. *(ps16)*
- [x] 5.8 **RED.** `theSearchPromptStillCountsCatalogRecordsOnly`: `PaneSearchField`'s prompt still reads
      `Search \(catalog.packageCount.formatted()) packages…` — unchanged, tap hits uncounted
      (`BrowseView.swift:45-48`). And `theEmptyStateYieldsToTapHits`: the overlay condition becomes
      `rows.isEmpty && tapHits.isEmpty`, so a query matching only tap packages shows the section rather
      than `EmptyResults` (`:74-78`). *(ps13, PS8's prompt clause, R5)*
- [x] 5.9 **RED — DD-11a, the one edit to a shipped guard.** `cellarTests/PerPackageTrustCompositionTests.swift`:
      add `"cellar/Browse/BrowseView.swift"` and `"cellar/Browse/TapSearchSection.swift"` to
      `PerPackageTrustSources.views()` (`:186-201`) and extend the sorted-name anchor (`:31-32`) to
      `["BrowseView.swift", "PackageDetailView+Receipt.swift", "PackageDetailView.swift", "TapDetailView.swift", "TapSearchSection.swift", "TapsListView.swift"]`
      — ASCII order: `B` first, `+` (U+002B) before `.` (U+002E), `TapD` < `TapS` < `Taps`. **Exactly 3
      lines.** Both new files then inherit the shipped `for source in sources` guards (`:60-75`): no
      `"Trusted individually"`, no `trusted individually`, no locally derived section case. Do **not**
      add a private second scanner in the new test file. *(ps15, R3)*
- [x] 5.10 **Prove RED** (5.1–5.9 all fail, each for its stated reason), then **GREEN**: new file
      `cellar/Browse/TapSearchSection.swift` — the row is name, `KindTag(kind:)`, tap of origin,
      `hit.stateCopy`, `hit.collisionNote`, and `MutationMenu` over the bare-target `PackageEntry`
      (**DD-9**). No copy literal of its own beyond the section title.
- [x] 5.11 **GREEN.** `cellar/Browse/BrowseView.swift` — the flat `List(rows, selection: $selection)`
      (`:59-78`) becomes `List(selection: $selection) { ForEach(rows) { … }; TapSearchSection(…) }`. The
      catalog rows move into a **bare `ForEach` with no header** (**DD-8**); the row builder, `.tag(entry.id)`
      and `.themedListSelection` move **byte-unchanged**. `tapHits` is built **synchronously in `body`** —
      no `Task`, no `.task {}`, no `await` (**DD-12**) — gated by `TapPackageSearch.isSectionVisible(…)`.
      **No `private` is relaxed anywhere** (**DD-10**, unlike m10's DD-9): `EmptyResults` stays private.
- [x] 5.12 **GREEN.** `cellar/ContentView.swift:307-315` — add **one** argument, `taps: taps`. Nothing
      else in that file changes; the store is already wired.
- [x] 5.13 Runner green — the Phase 0 baseline **plus** the new composition cases, and
      `PerPackageTrustCompositionTests` **both** tests still green with only the 3-line edit. Commit WU4
      (`feat(browse): show packages published by your taps below the catalog results`).

## Phase 6: Verification and bindings — **SUPERSEDED by Phase 6′**

> Tasks 6.1–6.6 ran at `dbc5233` and are true of **that** tree. They do **not** discharge the round-2
> scope change: 6.3's bindings proof predates the `BrowseView.swift` revert, and 6.5's count is 19, not
> 20. Re-run the equivalents in **Phase 6′**. Task 6.7 was never performed and is **VOID**.

- [x] 6.1 Full core suite: `swift test --package-path Packages/CellarCore` → the Phase 0 baseline **plus**
      every new case, **0 failures**. Assert counts, never a bare success line.
- [x] 6.2 App target — **use the SCOPED runner**:
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`
      → baseline plus the new composition cases, 0 failures. **The full `-scheme cellar` runner is known
      red on `main` @ 5a0860b** from two **pre-existing** `cellarUITests` Taps failures
      (`cellarUITests.swift:209`, `:231`), tracked for a separate PR — it is **not** the gate for this
      change, and a red full-scheme run caused by those two cases is **not** a regression of m11.
      `cellarUITests` gains **no** new test and has a zero-line diff on this branch.
- [x] 6.3 **Bindings proof.**
      `git diff --stat main -- cellar.xcodeproj/project.pbxproj openspec/specs/ Packages/CellarCore/Sources/Catalog/PackageSearchIndex.swift Packages/CellarCore/Sources/BrewClient/MutationCommand.swift Packages/CellarCore/Sources/BrewClient/TapCommand.swift Packages/CellarCore/Sources/BrewClient/TapProjection.swift cellar/Browse/PackageDetailView.swift scripts/ .github/workflows/`
      → **empty output**. A non-zero `project.pbxproj` diff means the file-system-synchronized group
      assumption broke; a non-zero `openspec/specs/` diff means someone promoted a delta early (that is
      `sdd-archive`'s job); a non-zero `PackageSearchIndex.swift` diff means the source was pushed
      **into** the index (Approach C, which PD6 now forbids outright); a non-zero `MutationCommand.swift`
      diff means a new argv family was invented (PM10). Any of them is reported before merge, never
      absorbed.
- [x] 6.4 **Regression guards that must never have moved**: `PerPackageTrustCompositionTests` (both
      tests, 3-line edit only), `TapProjectionTests`, `TapShippingProofTests`, `MutationCommandTests`,
      `MutationCommandTargetTests`, `SearchIndexTests`, `FilterTests`, `InstalledFilterCompositionTests`,
      `ReceiptDetailCompositionTests`, `PackageGraphTests`.
- [x] 6.5 **Spec-delta self-check before verify**: re-count the four deltas against task 1.2's numbers;
      confirm PD6's three, TM5's ten and TM11's two shipped scenarios are **byte-identical** to
      `openspec/specs/{package-detail,tap-management}/spec.md` (`git diff --no-index` on the extracted
      blocks); confirm every one of the **19** new scenarios has a task above naming it — **including
      ps4, whose RED row this artifact added** — and that **no** delta introduces a new verification
      class.
- [x] 6.6 `git diff --stat main` for the whole branch — record the authored total **split into the
      code+test bucket and the artifact bucket**, and compare each against its own forecast (1,509–2,608
      and the band task 0.4 fixed). If the total exceeds 5,000, record it as information for the next
      forecast, not as a mid-flight re-plan.
- [ ] 6.7 **VOID — never performed, superseded by task 6′.7.** Its "no `size:exception`" premise is
      false as of 2026-08-25 and its body text describes a Browse section that no longer exists. Kept
      only so the supersession is visible rather than silently rewritten. Original text follows.
      **Delivery — one PR** (`single-pr`, forecast Medium against 5,000; no `size:exception`, no
      chain). The body states up front: (a) the section **adds no brew invocation and no store** — it
      composes an inventory already resident, and PS6's 8 ms ceiling is measured on the combined turn;
      (b) it **reads no trust state and presents no badge or control** — an untrusted tap surfaces
      through the shipped typed refusal and its Trust recovery, never a pre-launch block (PM10);
      (c) **nothing enters the catalog** — no snapshot record, no index entry, one membership-only read;
      (d) **ambiguous and not-installed rows are deliberately inert** — the catalog-first resolution
      would otherwise open a different package than the row chosen; and (e) the **full-scheme** runner is
      red on `main` for two pre-existing UI reasons, so the scoped runners are the gate (task 6.2).

## Phase 7: Archive obligations — **SUPERSEDED by Phase 7′**

> Recorded against the rev-2 specs. PS8's scenario count, the withdrawn `From your taps` string and the
> milestone claim in 7.4 are all wrong after the scope change. **Phase 7′** replaces this wholesale.

- [x] 7.1 Promote the ADDED block as **PS8**, appended after `package-search`'s current last requirement
      (→ 8 req / 35 sc; PS1–PS7 byte-identical). Promote PD6, TM5 and TM11 as **whole-block
      replacements** (→ 8 req / 32 sc and 13 req / 60 sc). **Promote no verification-class table** —
      none of the three main specs carries one (precedent at
      `openspec/specs/installed-inventory/spec.md:1122-1184`); only the inline `- Verification:` lines
      promote. `package-search` and `package-detail` carry **no `<!-- PS# -->` / `<!-- PD# -->` markers**;
      match those blocks by heading.
- [x] 7.2 Record in provenance: **no `package-mutation` delta** — PM10 was **activated, not amended**,
      and its argv enumeration gains no family; **no `installed-inventory` delta** — II7/II8/II15
      activated; **no `package-trust` delta** — nothing on this surface reads a grant; **TM12 untouched**
      — no Untrusted badge in Browse. Record the **TM10→TM11 / TM11→TM12 marker drift** once more, since
      `explore.md` and `proposal.md` still carry the pre-promotion ordinals.
- [x] 7.3 Record the deferrals, so a future contributor does not “complete the grid”: a **name-only
      detail pane for a not-installed tap hit** is a clearly scoped follow-up, blocked today by TM5's
      unconditional tap-source-read ban; **a merged ranked list** stays rejected (PS3's order is broken
      by 365-day install count, which a tap package does not have); **index ingestion** (Approach C) is
      now explicitly forbidden by PD6's modified text; **`SearchFilters` gains no member** for this
      source, by construction.
- [x] 7.4 Record which **PRD.md milestone** this closes (**M11**), and note that the two pre-existing
      `cellarUITests` Taps failures (`:209`, `:231`) remain open and are **not** m11's to close.
      **CORRECTED in round 2 (task 7′.4): no PRD milestone is closed — `PRD.md` §7 ends at M6.**

---

# Round 2 — scope change (2026-08-25, binding)

**Maintainer scope change, binding.** Tap results leave Browse entirely and get **their own sidebar
surface**. This section describes the delta from **`dbc5233`**, not from `main`.

| | Round 1 (landed) | Round 2 (this) |
|---|---|---|
| Where tap results appear | a `Section` inside `BrowseView`'s list | **its own sidebar section**, `Search our taps` |
| `cellar/Browse/BrowseView.swift` | modified (sectioned list, `let taps`, overlay) | **reverted to a ZERO diff vs `main`**, asserted |
| Empty query | section hidden | **lists every tap package**, deterministic order |
| Outdated chip | hid the section | **does not exist** on this surface |
| Absence | `isSectionVisible` (a `Bool`) | a **presentation state machine** with pinned empty-state copy |

Inputs: `proposal.md` **r2**, `specs/**` **r3**, `design.md` **r3** (DD-1…DD-17), maintainer decisions
and the verified SF Symbol in Engram topic `sdd/m11-tap-search/state` (obs `#7795`). Engram mirrors:
spec `#7798`, design `#7797`.

## Scenario map — round 2 (rev 3 specs; **20** new scenarios)

**`package-search` PS8 — now 17 scenarios (12 `unit`, 5 `unit-app`).**

| ID | Scenario | Class | Round-2 status |
|---|---|---|---|
| **ps1** | found by a non-empty query | `unit` | green, untouched |
| **ps2** | token-aware ladder | `unit` | green, untouched |
| **ps3** | total and reproducible order | `unit` | green, untouched |
| **ps4** | five facts and its copy, nothing else | `unit` | green, untouched |
| **ps5** | kind filter restricts | `unit` | green, untouched |
| **ps6** | **an empty query lists everything the installed taps publish** | `unit` | **REWRITTEN — inverts round 1** |
| **ps7** | **an unavailable or empty inventory is an ordinary empty state, never an error** | `unit` | **REWRITTEN — copy is new** |
| **ps8** | collision reported, never suppressed | `unit` | green, untouched |
| **ps9** | three install states, exact copy | `unit` | green, untouched |
| **ps10** | ambiguous installed hit not routable | `unit` | green, untouched |
| **ps11** | **hide-installed composes above; no outdated control exists** | `unit` | **half green** (hide-installed), **half new** (no outdated predicate) |
| **ps12** | **the tap surface holds the ceiling on its OWN turn; PS6 unchanged** | `unit` | **REWRITTEN — no longer a combined turn** |
| **ps13** | **its own titled entry; not-installed rows inert** | `unit-app` | **REWRITTEN** |
| **ps14** | installed hit opens the receipt-backed detail | `unit-app` | green, **retarget the scan** |
| **ps15** | no trust gate, no local copy | `unit-app` | green, **retarget the scan** |
| **ps16** | composing reaches no process layer | `unit-app` | green, **retarget the scan** |
| **ps17** | **the catalog query surface is untouched (zero-line diff)** | `unit-app` | **NEW** |

**`package-detail` PD6 sc4**, **`tap-management` TM5 sc11**, **TM11 sc3** — all `unit`, all **green from
round 1**. Their prose was amended in r3; task 1′.2 confirms the amendment did not move what the
shipped tests assert.

**Totals: 20 new scenarios (15 `unit`, 5 `unit-app`)** — PS8 17 + PD6 1 + TM5 1 + TM11 1.
**Round-2 RED work: 9 scenarios** (ps6, ps7, ps11's new half, ps12, ps13, ps14, ps15, ps16, ps17).
**11 stay green untouched.** No `manual-evidence` scenario exists — the latency rows are runner rows.

**Round-1 tests to DELETE** (the behaviour no longer exists — leaving them green would pin a rule the
spec withdrew): `theSectionIsAbsentForAnEmptyOrWhitespaceQuery`, `theOutdatedChipHidesTheSection`,
`theTapSectionIsTitledAndPositionedLast`, `theEmptyStateYieldsToTapHits`, `catalogRowSelectionIsUnchanged`,
`theSearchPromptStillCountsCatalogRecordsOnly` (Browse form), `browseComposesTheTapSectionFromTheResidentStore`.

### RED-map reconciliation — round 2 (the design's open obligation, discharged)

Matched `design.md` r3's Testing Strategy table against the r3 specs, scenario by scenario.

1. **Gap: ps11's second clause.** “the controls this surface offers are enumerated and contain **no
   outdated predicate**” is delivered at class **`unit`**, but the design answers it only at `unit-app`
   (`theTapFilterBarOffersNoInertControl`, a view scan). A view scan cannot discharge a `unit`
   scenario. **Task 2′.5 supplies the missing `unit` row** — the projection's parameter surface admits
   no outdated predicate at all — and the `unit-app` row is kept as the view-side half.
2. **Carried gap, already discharged.** ps4 still has no design row; round 1's task 2.5 shipped
   `aHitCarriesItsFiveFactsAndItsCopyAndNothingElse` and it stays green. No action.
3. **`design.md` does not quote the two empty-state strings.** DD-17 says the surface's copy is “pinned
   by the spec” and stops there. **The spec is the source**: `No packages from your taps.` and
   `Your taps publish nothing yet.`, verbatim from `specs/README.md:53-54` and
   `specs/package-search/spec.md:236-237`. `sdd-apply` reproduces those bytes and must **not** take a
   paraphrase from the design.
4. **Copy ownership, resolved by verification class.** `specs/README.md:61-62` reads as though the two
   empty-state strings “belong to the surface”, but ps7 is class **`unit`** — a CellarCore test cannot
   reach a SwiftUI view. They therefore live in the **projection** (`TapSearchPresentation`), and the
   view renders them. That is also what DD-6/DD-17 and the round-2 brief require.
5. Confirmed: the delivered blocks still number the added requirement **PS8** and still target **TM5 +
   TM11** (the main spec's markers).

## Pinned copy — round 2 (apply reproduces these bytes, it does not choose them)

| Fact | Exact copy | Where it lives |
|---|---|---|
| Sidebar entry + surface title | `Search our taps` | `AppSection.sidebarTitle` **and** the surface — both, byte-identical |
| `AppSection.title` | `Search taps` | `AppSection.swift` title arm (**DD-14** site 1) |
| Empty state — inventory unavailable | `No packages from your taps.` | the **projection** (`brewAbsent` **and** failed refresh) |
| Empty state — nothing published | `Your taps publish nothing yet.` | the **projection** (available, no third-party tap publishes) |
| Catalog collision note | `Also in the catalog. Homebrew installs the catalog package.` | the **projection** only |
| Install state — installed | ~~`Installed.`~~ **WITHDRAWN round 3** | replaced by `StatusPill.installed`, whose `Installed` label lives in `cellar/Browse/StatusPill.swift` |
| Install state — tap withheld | `Installed. Homebrew withholds its tap while this tap is untrusted.` | the **projection** only — **and** the pill beside it (round 3) |
| Install state — not installed | ~~`Not installed.`~~ **WITHDRAWN round 3** | nothing at all: no copy, no pill |

`From your taps` is **WITHDRAWN** — it named a section that no longer exists. It must appear **nowhere**
in the tree after WU7. `Installed.` and `Not installed.` are **WITHDRAWN for this surface** by round 3;
neither may be produced, whole, by `TapPackageSearch.swift` or `TapSearchView.swift`. Both survive
unchanged in `TapProjection.statusExplanation` for the tap-detail rows TM5 governs — do not delete them
there. A non-empty query matching nothing reuses the ordinary no-match empty state; **no
copy is pinned for it**, so do not invent one.

**SF Symbol.** `AppSection.tapSearch`'s `systemImage` MUST be **the symbol recorded in Engram topic
`sdd/m11-tap-search/state`, verified against this SDK** — never a guessed name. `AppSection.swift:148-150`
already records one case where a plausible name did not exist on this SDK. Read the topic; do not
substitute a candidate from the design's open-question list without re-verifying it.

## Review Workload Forecast

| Field | Value |
|---|---|
| Round 1, **measured** at `dbc5233` | **4,404** authored lines on the branch |
| Round-2 **gross churn** (design r3 File Changes) | **~946–1,006** edited lines across 13 files |
| Round-2 **net PR-diff delta** | **+150–200** — the number that matters. `TapSearchSection.swift` is created **and** deleted on this branch, so it nets to **0** vs `main`; the `BrowseView.swift` revert nets to **−45**. Gross churn and PR diff are not the same measurement, and confusing them is how this branch appears to be 5,400 lines when it is not |
| Code + tests bucket (derived, re-measure at 0′.1) | ~1,907 (round 1) → **~2,057–2,107** |
| **SDD artifacts, counted from disk, no code-derived correction** | **2,193** now on the branch (proposal 209 · design 340 · specs 911 · explore 572 · apply-progress 161) + this file, **counted after this amendment at 918** + `verify-report.md` **250–450** at verify time = **3,361–3,561** |
| Estimated PR total | **~5,418–5,668** |
| Maintainer's accepted projection | **4,900–5,200** (obs `#7795`, 2026-08-25) |
| Recount variance, reported not hidden | **+218 to +468** above the accepted ceiling. **Every line of it is artifact**, not code: three artifact revisions (proposal r2, specs r3, design r3) plus a two-round tasks file that is itself **918** lines. The code+test bucket is **inside** its forecast, and the round-2 code delta is a net **+150–200** |
| Governing budget | **5,000** (`config.yaml:8`) — **not gating**: `size:exception` is accepted |
| Chained PRs recommended | **No** — one PR, five round-2 work units, delivered as work-unit commits |
| Suggested split | **Single PR** under the accepted exception |
| Delivery strategy | single-pr |
| Chain strategy | pending — no chain in play |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High
size:exception: accepted (maintainer, 2026-08-25)

`400-line budget risk` is the literal guard value against the 400 **default**, which does not govern
this repository. The 5,000-line project budget is exceeded by artifact lines alone, and the maintainer
**accepted `size:exception` for this single PR on 2026-08-25**, so `sdd-apply` starts without a chain
decision and without re-asking. The recount variance above is **information for the next forecast**, not
a re-plan.

**Branch**: `feat/m11-tap-search` (unchanged — round 2 continues it).
**PR title**: `feat(taps): search and install packages published by your taps`.

### Round-2 Work Units (`work-unit-commits`; conventional commits, **no `Co-Authored-By`, no AI attribution**)

| Unit | Goal | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU5** | The amended artifacts land **first** — proposal r2, specs r3, design r3, this file | N/A — artifacts only | N/A — no behaviour changes | Revert one docs commit; the branch returns to `dbc5233` |
| **WU6** | Projection amendments: **DD-16** empty query lists all · **DD-6** `presentation(…)` replaces `isSectionVisible` · **DD-17** `packageCount` — ps6, ps7, ps11's new half | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | N/A — a pure projection over resident values; there is no runtime to exercise | Revert one commit in `TapPackageSearch.swift` + its test file; no app file depends on it yet |
| **WU7** | The surface swap: **revert `BrowseView.swift`**, delete `TapSearchSection.swift`, add `AppSection.tapSearch` at nine sites, add `TapSearchView.swift`, `ContentView` wiring, `CatalogFilterBar` flags | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` | **Launch the app**: the sidebar shows `Search our taps` under Overview; an empty query lists every tap package; typing narrows; Browse looks and behaves exactly as on `main` | `git checkout dbc5233 -- cellar/` restores the round-1 surface wholesale |
| **WU8** | Rewrite `TapSearchCompositionTests` — retarget every scan to `TapSearchView.swift`, add the Browse zero-diff row, the AppSection wiring row, the empty-state-copy-in-projection row; retarget `PerPackageTrustSources` — ps13–ps17 | `xcodebuild test … -only-testing:cellarTests` | N/A — source-scan suite; the app harness is WU7's | Revert one test commit; no production line is its own |
| **WU9** | Latency, **split**: the tap surface's own turn (p95 < 8 ms) **and** PS6's catalog measurement re-run **unchanged** — ps12 | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | N/A — the measurement is the harness | Revert the two test cases and the ~500-package fixture builder |

**Parallel vs sequential.**

- **Sequential, hard dependencies**: **WU5 → everything** (the r3 specs are what make the round-1
  behaviour wrong; code that lands first contradicts an artifact still on disk). **WU6 → WU7** (the view
  renders `TapSearchPresentation`, which does not exist yet). **WU7 → WU8** (every WU8 scan reads
  `TapSearchView.swift`; a scanner pointed at a missing path **throws**, it does not fail cleanly —
  **DD-11**). **WU6 → WU9** (the latency row calls `presentation(…)` on the same turn).
- **Parallelisable in principle**: **WU9 ∥ WU7/WU8** once WU6 is green — disjoint files and runners.
  **One writer, executed sequentially** — no parallel worktrees, no parallel branches.
- **Inside every unit**: RED before GREEN, `strict_tdd: true`. Where the behaviour already exists,
  RED is obtained by **mutation**: change the assertion to the new expectation and watch it fail against
  the shipped implementation. A row that never went red proves nothing.
- **Rollback order** is the reverse — WU9 → WU8 → WU7 → WU6 → WU5.
- **Bottleneck**: **WU7** — nine wiring sites of which four are compiler-forced and five are silent,
  a whole new view, a file deletion and a file revert, all in one commit that must keep the app
  compiling. **Secondary: WU8**, because its scanners throw rather than fail when a path is wrong.

## Phase 0′: Preflight round 2 (sequential; no behaviour changes)

- [x] 0′.1 Re-measure the branch: `git diff --stat main` at `dbc5233` — record the authored total split
      into **code+test** and **artifact** buckets. This replaces the derived ~1,907 above with a measured
      number, and is the base every later comparison uses.
- [x] 0′.2 Confirm the round-2 anchors — a moved anchor is a deviation to **report, not absorb**:
      `TapPackageSearch.swift` :125 (the `guard needle.isEmpty == false else { return [] }` DD-16
      removes), :88-123 (`hits(…)`), the `isSectionVisible` declaration DD-6 deletes ·
      `TapProjection.swift` :188-196 (`state(loadState:inventory:)`) · `TapProjectionTests.swift` :130-135
      (`presentationStatesRemainDistinct`, incl. the `hasLastGood` rule) · `PackageSearchIndex.swift`
      :218-227 (`defaultOrder`, the empty-query precedent DD-16 mirrors) · `AppSection.swift` :28
      (`case browse`), :104-130 (`title`), **:134-139 (`sidebarTitle` — HAS a `default:` arm)**,
      :141-167 (`systemImage`), :173-180 (`sidebarGroups`), :148-150 (the recorded missing-symbol
      precedent) · `ContentView.swift` :68 (`@State … section`), :97-99, :156-159, :204-206, :306,
      :530-546, :594-599, :603-606, :624-636 · `SidebarView.swift` :175-205 · `CatalogFilterBar.swift`
      :10-16, :77-95 · `AppSectionPlacementTests.swift` :34 (`order.count`), :52-60 (rawValue anchor),
      :150-156 (the AppSection-switch count), :195-200 (the `allCases` membership loop) ·
      `TapSearchCompositionTests.swift` :287-291 (`TapSearchSources.paths`) ·
      `PerPackageTrustCompositionTests.swift` :31-32, :186-201.
- [x] 0′.3 **Read the SF Symbol from Engram** — `mem_search("sdd/m11-tap-search/state")` →
      `mem_get_observation` — and record the **verified** symbol name in the apply context. Do **not**
      guess, and do **not** take a name from `design.md`'s open-question candidate list without
      re-verifying it against this SDK.
- [x] 0′.4 Record the **current** green baseline on the branch (both scoped runners, distinct passing
      test ids). Round 1's Phase 0 numbers are for `main`, not for `dbc5233`.

## Phase 1′: WU5 — the amended artifacts land first

- [x] 1′.1 Commit `proposal.md` r2, `specs/**` r3, `design.md` r3 and this file before any Swift change:
      `docs(sdd): record the m11-tap-search scope change to its own tap search surface`.
      **Acceptance**: the specs pin `Search our taps`, the two empty-state strings, the empty-query
      listing rule, the absence of an outdated control, the per-surface latency ceiling and the
      zero-diff `BrowseView` claim — and **withdraw** `From your taps`.
- [x] 1′.2 Confirm the delta arithmetic against r3: `package-search` **1 ADDED / 17 scenarios** → 8 req /
      36 sc; `package-detail` **1 MODIFIED, 4 replacing 3** → 8 req / 32 sc; `tap-management` **2
      MODIFIED, 11 replacing 10 and 3 replacing 2** → 13 req / 60 sc; **20 new scenarios total**. Then
      confirm the r3 prose amendments to **PD6, TM5 and TM11 did not move what the round-1 tests assert**
      — those three suites must still be green with **no edit**. A needed edit is a spec defect to
      report, not to patch here.
- [x] 1′.3 Record that `design.md` **does not quote** the two empty-state strings and that **the spec is
      authoritative** for them (reconciliation finding 3), so no later task paraphrases them.

## Phase 2′: WU6 — the projection amendments (ps6, ps7, ps11's new half)

Runner: `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'`

- [x] 2′.1 **RED by mutation.** In `TapPackageSearchTests.swift`, **rewrite**
      `theSectionIsAbsentForAnEmptyOrWhitespaceQuery` into `anEmptyQueryListsEveryTapPackage`: two taps
      publishing forty packages between them; `""` **and** `"   "` each return **all forty**, each at
      `.exactToken`, ordered by bare token, then kind, then tap name; nothing thrown, nothing withheld;
      official taps still excluded; `kinds` and `hideInstalled` still applied. **RED because** `:125`
      still returns `[]`. *(ps6, DD-16)*
- [x] 2′.2 **RED.** `theDefaultListingOrderMatchesTheSearchOrder`: the empty-query listing and a query
      that matches everything produce the **same sequence**, so one order governs both. *(ps6, DD-16)*
- [x] 2′.3 **RED.** `thePresentationDistinguishesEveryEmptyReason`: `.brewAbsent` ⇒ `.unavailable(absence)`;
      a failed refresh ⇒ `.failed(error)`; `.loaded` with no third-party tap ⇒ `.noTaps`; loaded with taps,
      a non-empty query and `hitCount == 0` ⇒ `.noMatch(query:)`; `hitCount > 0` ⇒ `.content`. Five
      **distinct** values, and **no absence is reported as an error value**. **RED because**
      `TapSearchPresentation` does not exist. *(ps7, DD-6)*
- [x] 2′.4 **RED.** `thePresentationKeepsStaleContentWhileRefreshing`: `.loading` over a non-empty
      resident inventory does **not** collapse to `.loading` and hide rows — the `hasLastGood` rule is
      **inherited** from `TapProjection.state(…)` (`:188-196`, proven by
      `TapProjectionTests.presentationStatesRemainDistinct` `:130-135`), never re-derived from
      `TapLoadState`. A second opinion here is exactly the drift PT5's one-projection rule forbids.
      *(ps7, DD-6)*
- [x] 2′.5 **RED — the row the design's table places at the wrong class (reconciliation finding 1).**
      `theTapSourceAdmitsNoOutdatedPredicate`: enumerate the projection's parameter surface — `hits(…)`
      takes `query`, `kinds`, `hideInstalled`, `isInCatalog` and **nothing else**; there is **no**
      `outdatedOnly` parameter and **no** `isSectionVisible` symbol left to carry one. `hideInstalled`
      still subtracts (the shipped `hideInstalledSubtractsFromTheSection` stays green). **RED because**
      `isSectionVisible` still exists. *(ps11, DD-6, DD-15)*
- [x] 2′.6 **RED.** `theEmptyStateCopyIsExact`: each `TapSearchPresentation` case maps to its pinned
      sentence **byte-for-byte** — `.unavailable` **and** `.failed` both to `No packages from your taps.`,
      `.noTaps` to `Your taps publish nothing yet.` — and none is empty. Copy comes from
      `specs/package-search/spec.md:236-237`, **not** from `design.md`, which does not quote it.
      *(ps7, DD-17)*
- [x] 2′.7 **RED.** `thePackageCountCountsThirdPartyTapsOnly`: `packageCount(inventory:)` equals the hit
      count for an empty query under default filters, and excludes `homebrew/core` / `homebrew/cask`.
      **RED because** the function does not exist. *(DD-17)*
- [x] 2′.8 **Delete, do not leave green.** Remove `theOutdatedChipHidesTheSection` — the behaviour is
      withdrawn, and a passing test for a withdrawn rule is worse than no test.
- [x] 2′.9 **Prove RED.** 2′.1–2′.7 MUST fail, each for its stated reason.
- [x] 2′.10 **GREEN.** `TapPackageSearch.swift`: remove the `:125` empty-needle guard and assign an empty
      needle `.exactToken` for **every** package (**DD-16**, mirroring `PackageSearchIndex.swift:218-227`);
      **delete** `isSectionVisible(query:outdatedOnly:tapState:)`; add
      `public enum TapSearchPresentation: Sendable, Equatable { case loading, unavailable(InstalledAbsence),
      failed(TapInventoryError), noTaps, noMatch(query: String), content }`, the static
      `presentation(tapState:inventory:query:hitCount:)` built by **switching over**
      `TapProjection.state(loadState:inventory:)`, its pinned copy, and
      `static func packageCount(inventory:) -> Int`.
- [x] 2′.11 **GREEN, binding constraints**: matching, ladder, order, collision rule and every hit-level
      string stay **byte-unchanged** (**DD-1…DD-5, DD-7, DD-9** are shipped and must not be re-litigated);
      still `nonisolated` by module default, no annotation, no `@unchecked`, no actor (**DD-12**); no
      `Process`, `FileManager`, store, clock, SwiftUI import or `#available` (**DD-13**).
- [x] 2′.12 Focused command green **and** `TapProjectionTests` / `SearchIndexTests` / `FilterTests` still
      green; commit WU6 (`feat(search): list every tap package for an empty query and name each empty state`).

## Phase 3′: WU7 — the surface swap (nine wiring sites, one revert, one deletion)

Runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`

> `cellar/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup`s (`project.pbxproj` :46, :51),
> so both the new file **and the deletion** are a **0-line `project.pbxproj` diff**.

- [x] 3′.1 **Revert, do not hand-unpick**: `git checkout main -- cellar/Browse/BrowseView.swift`. A
      hand-revert is how a stray blank line survives and turns a zero-diff claim into a review argument.
      Then `git diff main -- cellar/Browse/BrowseView.swift` MUST print **empty output**. *(DD-8)*
- [x] 3′.2 `git rm cellar/Browse/TapSearchSection.swift`. No file may reference it afterwards; the two
      scanner lists are updated in **this same commit** (3′.9, 4′.1) or their reads **throw**. *(DD-11)*
- [x] 3′.3 `cellar/ContentView.swift` — remove `taps: taps` from the `BrowseView(` call added in round 1.
      The store stays wired; `TapSearchView` consumes it now.
- [x] 3′.4 `cellar/Shell/AppSection.swift` — add `case tapSearch` **immediately after `.browse`** (`:28`),
      rawValue `"tapSearch"`. Sites 1–4: `title` ⇒ `Search taps`; **`sidebarTitle` ⇒ `Search our taps`
      — this arm has a `default:` (`:134-139`), so a missing case is SILENT and falls back to `title`;
      it is the one wiring site the compiler will not catch**; `systemImage` ⇒ the **Engram-recorded,
      SDK-verified** symbol (task 0′.3), distinct from `.browse`'s `magnifyingglass`; `sidebarGroups`
      ⇒ `("Overview", [.home, .browse, .tapSearch])`.
- [x] 3′.5 `cellar/ContentView.swift` — sites 5–8: add to `listSections` (`:156-159`); content switch
      `case .tapSearch: TapSearchView(…)` (`:306`); **join** the existing `PackageDetailView` detail arm
      beside `.browse, .installed, .favorites, .updates` (`:530-546`) — **no new branch** (**DD-4**);
      join the `nil` arm of `shellTitleBarAccessories` (`:624-636`).
- [x] 3′.6 `cellar/ContentView.swift` — the two `Set` literals, **not** switches and therefore silent:
      `pinnedHeaderSections` (`:594-599`, looped over `allCases` by
      `AppSectionPlacementTests.swift:195-200`) and `shellTitleBarSections` (`:603-606`). Plus
      `defaultListPaneWidth(for:)` (`:97-99`) → `.tapSearch` joins `.browse`'s **400** branch, and
      `countLabel` (`:204-206`) → the same shape over `TapPackageSearch.packageCount(inventory:)`
      (**DD-17**).
- [x] 3′.7 `cellar/Shell/SidebarView.swift:175-205` — site 9: join the no-badge arm (exhaustive, no
      `default:`).
- [x] 3′.8 `cellar/Browse/CatalogFilterBar.swift` — add `var showsOutdatedChip = true` and
      `var showsCatalogPredicates = true`. **Both MUST default**, because a non-defaulted parameter forces
      a `BrowseView.swift` edit and breaks 3′.1's zero diff outright. *(DD-15)*
- [x] 3′.9 **GREEN.** New file `cellar/Browse/TapSearchView.swift` — a visually exact sibling of Browse:
      `PaneSearchField` (prompt over `packageCount`, **never** a catalog record count),
      `CatalogFilterBar(showsOutdatedChip: false, showsCatalogPredicates: false, outdatedOnly: .constant(false))`,
      `List(selection:)` with the same row composition (`KindTag`, tap of origin, `hit.stateCopy`,
      `hit.collisionNote`, `MutationMenu(center:entry:)`, `.themedListSelection`), `.tag(hit.routableID)`
      with `.selectionDisabled()` for non-routable rows, and `@State private var selection: PackageID?`
      of its own. Built **synchronously in `body`** — no `Task`, no `.task {}`, no `await` (**DD-12**).
- [x] 3′.10 **GREEN.** In the same file, a **private** `TapSearchEmptyState` rendering
      `TapSearchPresentation`. **Duplication is forced, not chosen** (**DD-10**): `EmptyResults` is
      `private` at `BrowseView.swift:173` and Swift `private` is file-scoped, so any reuse — or any
      extraction to a third file — edits `BrowseView.swift` and breaks 3′.1. **Relax no visibility
      anywhere.** The view renders the projection's strings; it composes none.
- [x] 3′.11 The app compiles and the runner is green at the 0′.4 baseline; commit WU7
      (`feat(taps): give tap package search its own sidebar surface`).

## Phase 4′: WU8 — the composition guards (ps13–ps17)

Runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`

- [x] 4′.1 **Path swap first, in both scanners** — a scanner pointed at a deleted path **throws**, which
      reads as a suite-wide error rather than a clean failure: `TapSearchSources.paths`
      (`TapSearchCompositionTests.swift:287-291`) swaps `TapSearchSection.swift` → `TapSearchView.swift`
      and **keeps** `BrowseView.swift` (now as the subject of the zero-diff row);
      `PerPackageTrustSources.views()` (`:186-201`) swaps the same path and **drops `BrowseView.swift`**,
      because it is reverting to a file that never mentioned trust. Update the sorted anchor (`:31-32`)
      to `["PackageDetailView+Receipt.swift", "PackageDetailView.swift", "TapDetailView.swift", "TapSearchView.swift", "TapsListView.swift"]`
      — ASCII: `+` (U+002B) before `.` (U+002E), `TapD` < `TapSe` < `Taps`. *(DD-11)*
- [x] 4′.2 **RED.** `browseIsUntouchedByThisChange` — the load-bearing row: `BrowseView.swift` contains
      **none** of `TapPackageSearch`, `TapSearchHit`, `TapSearchSection`, `TapSearchView`, `TapStore`,
      `taps`, `tapHits`; it still declares `List(rows, selection: $selection)` and the single-source
      overlay `if rows.isEmpty {`; and `ContentView`'s `BrowseView(` call site carries no `taps:`.
      **Both** this row and the `git diff` in 3′.1 — the test is what protects the property after merge.
      *(ps17, DD-8)*
- [x] 4′.3 **RED.** `theTapSearchSectionFileIsGone`: no source under `cellar/` references
      `TapSearchSection`, and the scanner path lists name `TapSearchView.swift`. *(ps17, removal plan)*
- [x] 4′.4 **RED.** `theTapSearchSurfaceIsWiredAtEveryAppSectionSite`: `AppSection.tapSearch` exists with
      rawValue `"tapSearch"`, sits **immediately after `.browse`** in `allCases`, carries `Search taps`
      as `title` and **`Search our taps` as `sidebarTitle`** (asserted separately — the `default:` arm at
      `:134-139` makes a missing case silent), carries the SDK-verified `systemImage` distinct from
      `.browse`'s, appears in `sidebarGroups[0]` after `.browse`, and is a member of `listSections`,
      `pinnedHeaderSections` and `shellTitleBarSections`. *(ps13, DD-14)*
- [x] 4′.5 **RED.** `AppSectionPlacementTests.swift` amended, **not weakened**: `order.count` `21` → **22**
      (`:34`); `"tapSearch"` added **after** `"browse"` in the rawValue anchor (`:52-60`); the Overview
      group literal updated; sidebar coverage still **exact**; and `ContentView.swift`'s AppSection-switch
      count still **3** (`:150-156`) — this change adds cases to existing switches, never a fourth switch.
      *(ps13, DD-14)*
- [x] 4′.6 **RED.** `theTapSurfaceMirrorsBrowsesComposition`: `TapSearchView.swift` composes
      `PaneSearchField(`, `CatalogFilterBar(`, `List(selection:`, `KindTag(`, `MutationMenu(center:` and
      `.themedListSelection(` — the same six Browse's list uses. And `theTapSurfaceOwnsItsSelectionLocally`:
      it declares `@State private var selection: PackageID?`, and `ContentView`'s detail arm resolves
      `.tapSearch` through the **shared** `PackageDetailView` with **no new branch**. *(ps13, ps14, DD-4)*
- [x] 4′.7 **RED.** `theTapFilterBarOffersNoInertControl`: the call passes `showsOutdatedChip: false` and
      `showsCatalogPredicates: false`; `TapSearchView.swift` contains no `"Outdated"`, `"Hide deprecated"`
      or `"Hide disabled"` literal; and **both** new `CatalogFilterBar` parameters default to `true`, so
      the Browse call site needs no argument. *(ps11 view-side half, DD-15)*
- [x] 4′.8 **RED — retargeted scans** (mutation-based: the assertions exist, the subject file changes):
      `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge`, `theSurfaceCopyLivesInTheProjectionNotTheView`
      (now: the **six** projection strings — four hit strings **plus** the two empty-state sentences —
      present in `TapPackageSearch.swift` and **absent** from `TapSearchView.swift`; `Search our taps`
      present in `AppSection.swift` and the view), `neitherTapSearchFileReachesTheProcessLayer`,
      `notInstalledTapRowsAreNotSelectable`, `theReceiptDetailIsReachedWithNoNewRoutingBranch`,
      `theGrantCopyGuardCoversTheNewSurface`. **Plus**: `From your taps` appears **nowhere** in the tree.
      *(ps14, ps15, ps16)*
- [x] 4′.9 **Delete, do not leave green**: `theTapSectionIsTitledAndPositionedLast`,
      `theEmptyStateYieldsToTapHits`, `catalogRowSelectionIsUnchanged`,
      `theSearchPromptStillCountsCatalogRecordsOnly` (Browse form),
      `browseComposesTheTapSectionFromTheResidentStore`.
- [x] 4′.10 **Prove RED**, then GREEN — GREEN here should require **no production change**: WU7 already
      satisfies these absences. If any row needs a production edit, that is a **design deviation to
      report**, not to absorb. Commit WU8
      (`test(taps): pin the new surface and prove Browse is untouched`).

## Phase 5′: WU9 — latency, split per surface (ps12)

Runner: `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'`

- [x] 5′.1 **RED, restated from round 1.** `theTapSurfaceKeystrokeTurnStaysUnderTheCeiling`: a resident
      inventory of **≈500 packages across several taps**, **≥100** as-you-type queries of varying length,
      each turn running `hits(…)` **plus** `presentation(…)` **once** — p95 **< 8 ms**. It is **no longer
      a combined turn**: Browse composes no tap hits, so nothing is added to the catalog's budget. Adapt
      round 1's combined-turn row rather than deleting its fixture.
- [x] 5′.2 **RED.** `theCatalogKeystrokeTurnIsUnchanged`: PS6's shipped catalog measurement is re-run over
      **its own fixture, its own method, its own ceiling, with no tap inventory in its turn**, and must be
      **unchanged**. `BrowseView` and `PackageSearchIndex` are untouched, so a change here means something
      leaked. *(R6 in its new form)*
- [x] 5′.3 **The ceiling is not negotiable.** A miss is fixed in the projection — allocation per
      keystroke, repeated normalisation, an O(n·m) scan — **never** by a larger ceiling, a smaller
      inventory, fewer queries or a p90. A miss that survives optimisation is a design deviation to report.
      Note that DD-16 makes the **empty query the worst case** (every package matches), so measure it.
- [x] 5′.4 Focused command green; commit WU9
      (`test(search): pin each surface's keystroke turn under its own 8 ms ceiling`).

## Phase 6′: Verification and bindings (round 2)

- [x] 6′.1 Full core suite: `swift test --package-path Packages/CellarCore` → the 0′.4 baseline **plus**
      the new cases **minus** the deleted ones, **0 failures**. Assert counts, never a bare success line.
- [x] 6′.2 App target — **use the SCOPED runner**:
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`
      → 0 failures. **The full `-scheme cellar` runner is known red on `main` @ 5a0860b** from two
      **pre-existing** `cellarUITests` Taps failures (`cellarUITests.swift:209`, `:231`), tracked for a
      separate PR — it is **not** the gate for this change, and a red full-scheme run caused by those two
      cases is **not** an m11 regression. `cellarUITests` gains **no** new test and has a zero-line diff.
- [x] 6′.3 **Bindings proof.**
      `git diff --stat main -- cellar/Browse/BrowseView.swift cellar.xcodeproj/project.pbxproj openspec/specs/ Packages/CellarCore/Sources/Catalog/PackageSearchIndex.swift Packages/CellarCore/Sources/BrewClient/MutationCommand.swift Packages/CellarCore/Sources/BrewClient/TapCommand.swift Packages/CellarCore/Sources/BrewClient/TapProjection.swift cellar/Browse/PackageDetailView.swift scripts/ .github/workflows/`
      → **empty output**. `BrowseView.swift` is now first in that list and is the round-2 headline claim;
      a non-zero `project.pbxproj` diff means the synchronized-group assumption broke; a non-zero
      `openspec/specs/` diff means someone promoted a delta early; a non-zero `PackageSearchIndex.swift`
      diff means the source was pushed **into** the index (Approach C, which PD6 forbids); a non-zero
      `MutationCommand.swift` diff means a new argv family was invented (PM10). Any of them is reported
      before merge, never absorbed.
- [x] 6′.4 **Regression guards that must never have moved**: `TapProjectionTests`, `TapShippingProofTests`,
      `MutationCommandTests`, `MutationCommandTargetTests`, `SearchIndexTests`, `FilterTests`,
      `InstalledFilterCompositionTests`, `ReceiptDetailCompositionTests`, `PackageGraphTests`, and — with
      only their listed edits — `AppSectionPlacementTests` and `PerPackageTrustCompositionTests`.
- [x] 6′.5 **Spec-delta self-check before verify**: re-count the four deltas against 1′.2; confirm PD6's
      three, TM5's ten and TM11's two shipped scenarios are still **byte-identical** to
      `openspec/specs/{package-detail,tap-management}/spec.md`; confirm every one of the **20** new
      scenarios has a task naming it — including **ps11's `unit` half**, whose row this amendment added —
      and that **no** delta introduces a new verification class.
- [x] 6′.6 `git diff --stat main` for the whole branch — record the authored total split into code+test
      and artifact buckets, and compare each against the Round 2 forecast (~2,057–2,107 and 3,361–3,561).
      Record the **measured** total against the maintainer's accepted 4,900–5,200 and against this
      forecast's 5,418–5,668. A miss is information for the next forecast, not a failure.
- [ ] 6′.7 **Delivery — one PR** (`single-pr`, **`size:exception` accepted by the maintainer on
      2026-08-25**; no chain). The body states up front: (a) **Browse is byte-identical to `main`** — the
      catalog surface is out of scope, asserted by both a `git diff` and a test; (b) the surface **adds no
      brew invocation and no store** — it composes a resident inventory, and each surface holds its own
      8 ms turn; (c) it **reads no trust state and presents no badge or control** — an untrusted tap
      surfaces through the shipped typed refusal (PM10); (d) **nothing enters the catalog** — one
      membership-only read; (e) **ambiguous and not-installed rows are deliberately inert**; and (f) the
      PR is over the 5,000-line budget on **artifact lines**, under an accepted `size:exception`, with the
      full-scheme runner red on `main` for two pre-existing UI reasons (6′.2).

## Phase 7′: Archive obligations (round 2 — replaces Phase 7 wholesale)

- [x] 7′.1 Promote the ADDED block as **PS8** with its **17** scenarios (→ 8 req / **36** sc; PS1–PS7
      byte-identical). Promote PD6, TM5 and TM11 as **whole-block replacements** (→ 8 req / 32 sc and
      13 req / 60 sc). **Promote no verification-class table** — none of the three main specs carries one
      (precedent at `openspec/specs/installed-inventory/spec.md:1122-1184`); only the inline
      `- Verification:` lines promote. `package-search` and `package-detail` carry **no markers**; match
      by heading.
- [x] 7′.2 Record in provenance: **no `package-mutation` delta** (PM10 activated, argv enumeration gains
      no family); **no `installed-inventory` delta** (II7/II8/II15 activated); **no `package-trust`
      delta**; **TM12 untouched**. Record the **TM10→TM11 / TM11→TM12 marker drift** once more, since
      `explore.md` still carries pre-promotion ordinals.
- [x] 7′.3 Record the **withdrawn** string `From your taps` and the **void** rev-2 decisions (section
      placement, the Outdated chip hiding a section, `isSectionVisible`), so a future reader does not
      resurrect them from the round-1 history above or from `explore.md`.
- [x] 7′.4 **PRD milestone: none closed.** `PRD.md` §7 ends at **M6**; the m7–m11 labels are session
      shorthand, not PRD milestones. Do **not** record a closed milestone — round 1's task 7.4 claimed
      "M11" and is **wrong**. Also record that the two pre-existing `cellarUITests` Taps failures
      (`:209`, `:231`) remain open and are **not** m11's to close.
- [x] 7′.5 Record the deferrals: a **name-only detail pane** for a not-installed hit (blocked by TM5's
      tap-source-read ban); the **merged ranked list** stays rejected; **index ingestion** is forbidden by
      PD6's text; `SearchFilters` gains **no** member; and the tap surface knowingly holds a
      `SearchFilters` whose two exclusion predicates are dead (**DD-15**'s accepted cost).

---

# Round 3 — maintainer UI feedback (2026-08-25, binding)

Observed in the running app: a tap row carried a third text line reading `Installed.` or
`Not installed.`, where a catalog row carries the green **Installed** pill and shows **nothing** when a
package is not installed. The tap rows now mirror the catalog rows exactly. Delivery is unchanged:
**single-pr**, `size:exception` accepted (maintainer, 2026-08-25), `review_budget_lines: 5000` already
exceeded on artifact lines — report the measured total, never trim. Branch `feat/m11-tap-search`
continues from `8f233b1`.

**Scenario arithmetic does not move.** The change lands as amended clauses in PS8 plus amended bullets
inside two of its existing scenarios: `package-search` stays **1 ADDED / 17 scenarios** (→ 8 req / 36
sc), `package-detail` and `tap-management` are untouched by round 3. Nothing new is promoted.

## Round-3 Work Units (`work-unit-commits`; conventional commits, **no `Co-Authored-By`, no AI attribution**)

| Unit | Goal | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU10** | The amended artifacts land **first** — PS8's install-state clauses, `specs/README.md`'s copy table, `design.md` (DD-7 amended, DD-9 rewritten, DD-18 new, the round-3 RED rows) and this file | N/A — artifacts only | N/A — no behaviour changes | Revert one docs commit; the branch returns to `8f233b1` |
| **WU11** | `TapSearchHit.stateCopy: String` → `stateNote: String?` (withheld state only) plus a computed `isInstalled`; the two withdrawn constants deleted | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | N/A — a pure projection over resident values | Revert one commit in `TapPackageSearch.swift` + its test file. **Not independently revertible from WU12** — it changes a member the surface renders |
| **WU12** | `StatusPill` extracted from `PackageRow`; both surfaces draw it; the tap row loses its state sentence and keeps the withheld note | `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | **Launch the app**: an installed tap row shows the green `Installed` pill and no third line; a not-installed row shows no state text; a withheld row shows the pill **and** TM5's sentence; Browse's rows are unchanged | `git checkout 8f233b1 -- cellar/Browse/` restores all three files and deletes the new one |
| **WU13** | Composition guards: the withdrawn strings absent from both files, the shared pill asserted on both surfaces | `xcodebuild test … -only-testing:cellarTests` | N/A — source-scan suite; the app harness is WU12's | Revert one test commit; no production line is its own |

## Phase 1″: WU10 — the amended artifacts land first

- [x] 1″.1 Amend `specs/package-search/spec.md`: the five-facts paragraph, the install-state paragraph
      (pill for both installed states, TM5's sentence for the withheld one, nothing for not-installed,
      both strings **WITHDRAWN**), the ps4 scenario's THEN, the ps9 scenario (renamed to "…only the
      withheld state pins a sentence"), the ps15 scenario's scan clauses, the revision header and the
      archive notes. **Never touch `openspec/specs/**`.**
- [x] 1″.2 Amend `specs/README.md`: revision 4 header, the pinned-copy table's three install-state rows,
      the copy-ownership paragraph, and one new superseded row in the presentation-decisions table.
- [x] 1″.3 Amend `design.md`: **DD-7** amended, **DD-9** rewritten, **DD-18** new (the extraction), the
      round-3 file-changes table, the flow diagram's row line, and the round-3 RED rows.
- [x] 1″.4 Append this phase to `tasks.md` and mark the round-2 pinned-copy table's two withdrawn rows.
- [x] 1″.5 Commit `docs(sdd): amend m11-tap-search for the shared Installed pill on tap rows`.

## Phase 2″: WU11 — the install state becomes a fact (RED → GREEN)

- [x] 2″.1 **RED** in `TapPackageSearchTests.swift`, before any production edit: rename
      `theThreeInstallStatesCarryTheirExactCopy` → `onlyTheWithheldStateCarriesANote` and restate it —
      three distinct states; `isInstalled` true, true, false; `stateNote` `nil`, TM5's exact sentence,
      `nil`; and **neither withdrawn string produced for any hit**. Amend
      `aHitCarriesItsFiveFactsAndItsCopyAndNothingElse` (`Mirror` labels carry `stateNote`, the
      not-installed hit's note is `nil` rather than `""`) and the two spot assertions at the ambiguity
      and five-facts rows. Confirm the failure is a **compile** failure naming `stateNote`/`isInstalled`.
- [x] 2″.2 **GREEN** in `TapPackageSearch.swift`: `stateCopy: String` → `stateNote: String?`; add
      `public var isInstalled: Bool` computed from `state`, so no `Mirror` label is added; delete
      `installedCopy` and `notInstalledCopy`; `copy(for:)` → `note(for:) -> String?`.
- [x] 2″.3 Run `swift test --package-path Packages/CellarCore` whole — the guard is that no other core
      suite reads `stateCopy`, and that `TapProjectionTests`' own `statusExplanation` rows stay green.
- [x] 2″.4 Commit `feat(search): expose the tap install state as a fact instead of row copy`.

## Phase 3″: WU12 — the shared pill

- [x] 3″.1 Create `cellar/Browse/StatusPill.swift`: an internal `StatusPill: View` carrying
      `label`/`background`/`foreground`, the exact body `PackageRow.statusPill` had, and
      `static var installed` with the pinned `Installed` label and `Theme.successTint(0.16)` /
      `Theme.successText`. **No `project.pbxproj` edit** — `path = cellar` is a synchronized root group.
- [x] 3″.2 `PackageRow.swift`: delete `private func statusPill(…)`; the installed call site becomes
      `StatusPill.installed`, the badge loop becomes `StatusPill(label:background:foreground:)`.
      `BrowseView.swift` is **not** touched — verify with `git diff`.
- [x] 3″.3 `TapSearchView.swift`: draw `StatusPill.installed` after `KindTag` when `hit.isInstalled`;
      delete `state(_:)` and the unconditional third `Text`; render the note line only when
      `[hit.stateNote, hit.collisionNote]` joins to something non-empty.
- [x] 3″.4 `xcodebuild build …` → `** BUILD SUCCEEDED **`.
- [x] 3″.5 Commit `feat(taps): mark installed tap packages with the shared Installed pill`.

## Phase 4″: WU13 — the composition guards

- [x] 4″.1 `TapSearchCompositionTests.swift`: drop `"Installed."` and `"Not installed."` from
      `pinnedCopy`; add a `withdrawnCopy` list asserted **absent as complete literals** from the
      projection and the surface (a substring check would fail on the withheld sentence's first five
      characters); assert the surface carries no `"Installed"` literal at all, renders
      `StatusPill.installed`, `hit.stateNote` and `hit.collisionNote`; assert `PackageRow.swift` draws
      the same `StatusPill.installed`; assert `StatusPill.swift` declares the label exactly once.
- [x] 4″.2 Amend `notInstalledTapRowsAreNotSelectable`: `hit.isInstalled` leaves the forbidden list
      (the pill reads it, and a `Bool` about installation cannot express routability), and the row that
      replaces it asserts the pill is gated on `hit.isInstalled` while routability still comes from
      `hit.routableID` alone. `alsoInCatalog`, `hit.state ==` and `== .notInstalled` stay forbidden.
- [x] 4″.3 Decide and record whether `StatusPill.swift` joins `PerPackageTrustSources.views()`. It does
      **not**: that guard scans surfaces that present per-package trust, and the pill presents install
      state. Retarget nothing.
- [x] 4″.4 Prove RED for every new row by **reversible mutation** of the production files, restored
      byte-identically and `shasum -a 256 -c` verified.
- [x] 4″.5 Commit `test(taps): pin the shared Installed pill and the withdrawn row copy`.

## Phase 6″: Verification and bindings (round 3)

- [x] 6″.1 `swift test --package-path Packages/CellarCore` — record the total against the 1,870 baseline.
- [x] 6″.2 `xcodebuild test … -only-testing:cellarTests` — record against the 267 baseline. The full
      `-scheme cellar` runner is **not** the gate: it is red on `main` from two pre-existing
      `cellarUITests` Taps failures (`:209`, `:231`).
- [x] 6″.3 Bindings proof — `git diff --stat main --` over `cellar/Browse/BrowseView.swift`,
      `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `PackageSearchIndex.swift`,
      `MutationCommand.swift`, `PackageDetailView.swift` and `cellarUITests/` must print **nothing**.
- [x] 6″.4 `git diff --shortstat main...HEAD` — report the measured total under the accepted
      `size:exception`; never trim.
- [x] 6″.5 Commit apply-progress `docs(sdd): record the m11-tap-search round 3 apply progress`.

---

# Round 4 — maintainer UI feedback, the UPDATE pill (2026-08-25, binding)

Observed in the running app: round 3 gave the tap rows the catalog row's green **Installed** pill and
stopped there. An installed tap package whose own receipt already reports it outdated — `druk` at
`1.21.1` against the offered `1.22.1` — reads as merely installed on "Search our taps" while the same
package reads as updatable on the catalog surface and in the Installed list. The tap rows now carry the
**same shared orange UPDATE pill** (`PackageRow.swift:114`, already drawn by the Installed and Updates
lists), in the same position: after the Installed pill. Delivery is unchanged: **single-pr**,
`size:exception` accepted (maintainer, 2026-08-25), `review_budget_lines: 5000` already exceeded on
artifact lines — report the measured total, never trim. Branch `feat/m11-tap-search` continues from
`03be818`.

**Scenario arithmetic moves by two.** One `unit` scenario for the offered version and one `unit-app`
scenario for the shared component: `package-search` becomes **1 ADDED / 19 scenarios** (→ 8 req / **38**
sc; `unit` 12 → **13**, `unit-app` 5 → **6**). `package-detail` and `tap-management` are untouched by
round 4. No new copy is pinned — the pill's wording belongs to the shared component.

## Round-4 Work Units (`work-unit-commits`; conventional commits, **no `Co-Authored-By`, no AI attribution**)

| Unit | Goal | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU14** | The amended artifacts land **first** — PS8's six-facts and update-pill clauses, the two new scenarios, `specs/README.md`'s revision-5 header and copy table, `design.md` (**DD-19** new, the round-4 file-changes table and RED rows) and this file | N/A — artifacts only | N/A — no behaviour changes | Revert one docs commit; the branch returns to `03be818` |
| **WU15** | `TapSearchHit.nextVersion: String?`, stored, derived from the installed receipt through `TapPackage.installedHandoff` | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | N/A — a pure projection over resident values | Revert one commit across `TapPackageSearch.swift`, the two fixtures and the test file. **Independently revertible from WU16** this round: the member is added, never renamed, so the app target still compiles without it |
| **WU16** | The tap row draws `UpdateTag(nextVersion:)` after `StatusPill.installed` | `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | **Launch the app**: an installed, outdated tap row shows the Installed pill **and** the orange UPDATE pill, in that order; an up-to-date installed row shows only the Installed pill; a not-installed row shows neither; Browse's rows are unchanged | `git checkout 03be818 -- cellar/Browse/TapSearchView.swift` |
| **WU17** | Composition guards: the shared update pill on both surfaces, positioned, with no update copy in the tap view | `xcodebuild test … -only-testing:cellarTests` | N/A — source-scan suite; the app harness is WU16's | Revert one test commit; no production line is its own |

## Phase 1‴: WU14 — the amended artifacts land first

- [x] 1‴.1 Amend `specs/package-search/spec.md`: five facts → **six**, the offered-version paragraph, the
      update-pill paragraph, the narrowed reason for the still-absent Outdated control, the ps4 scenario
      renamed and restated, the new `unit` offered-version scenario, the new `unit-app` shared-update-pill
      scenario, the revision header, the class counts and the archive notes. **Never touch
      `openspec/specs/**`.**
- [x] 1‴.2 Amend `specs/README.md`: revision 5 header, the arithmetic row, one new pinned-copy row
      recording that **no** copy is pinned here, and one new presentation-decisions row.
- [x] 1‴.3 Amend `design.md`: **DD-19** new, the round-4 file-changes table, the flow diagram's row and
      source lines, the round-4 RED rows and the honesty note about `UpdateTag`'s declaring file.
- [x] 1‴.4 Append this phase to `tasks.md`.
- [x] 1‴.5 Commit `docs(sdd): amend m11-tap-search for the shared update pill on tap rows`.

## Phase 2‴: WU15 — the offered version becomes a fact (RED → GREEN)

- [x] 2‴.1 **RED** in `TapPackageSearchTests.swift`, before any production edit: a new
      `onlyAnOutdatedInstalledHitOffersAVersion` over a four-state fixture, and
      `aHitCarriesItsFiveFactsAndItsCopyAndNothingElse` renamed to `…SixFacts…` with `nextVersion` added
      to the `Mirror` label list. Confirm the failure is a **compile** failure naming `nextVersion`.
- [x] 2‴.2 Extend `InstalledFixture.receipt(…)` with a defaulted `outdatedTo: String? = nil` that sets
      `catalogVersion` and `snapshotOutdated` **together**, so an incoherent receipt is unrepresentable;
      add the outdated four-state inventory to `TapSearchFixture`.
- [x] 2‴.3 **GREEN** in `TapPackageSearch.swift`: `public let nextVersion: String?` on `TapSearchHit`,
      derived in `hits(…)` from `match.package.installedHandoff` → `installed.package(_:)` →
      `isOutdated ? catalogVersion : nil`. Stored, not computed — `Mirror` must see it.
- [x] 2‴.4 Run `swift test --package-path Packages/CellarCore` whole against the **1,870** baseline.
- [x] 2‴.5 Commit `feat(search): expose the offered version for an outdated installed tap package`.

## Phase 3‴: WU16 — the shared update pill on the row

- [x] 3‴.1 `TapSearchView.swift`: draw `UpdateTag(nextVersion: next)` under
      `if let next = hit.nextVersion`, immediately **after** `StatusPill.installed`. The second line
      (tap name) and everything below it are unchanged.
- [x] 3‴.2 `PackageRow.swift` and `StatusPill.swift` are **not** touched; `BrowseView.swift` stays
      byte-identical to `main` — verify all three with `git diff`.
- [x] 3‴.3 `xcodebuild build …` → `** BUILD SUCCEEDED **`.
- [x] 3‴.4 Commit `feat(taps): mark outdated tap packages with the shared update pill`.

## Phase 4‴: WU17 — the composition guards

- [x] 4‴.1 `TapSearchCompositionTests.swift`: a new `bothSearchSurfacesDrawTheOneSharedUpdatePill` —
      both files reference `UpdateTag(nextVersion:`; `struct UpdateTag: View` is declared exactly once
      across the app sources; the tap row's reference sits **after** its `StatusPill.installed` (range
      comparison, as the round-3 pill row does); the gate is `hit.nextVersion` alone; and
      `TapSearchView.swift` carries no `"UPDATE"` or `"Update"` literal.
- [x] 4‴.2 Prove RED by **reversible mutation** of `TapSearchView.swift`: (a) replace the shared pill
      with a local `Text("UPDATE")`; (b) move it **above** `StatusPill.installed`. Restore
      byte-identically and verify with `shasum -a 256 -c`.
- [x] 4‴.3 Commit `test(taps): pin the shared update pill on outdated tap rows`.

## Phase 6‴: Verification and bindings (round 4)

- [x] 6‴.1 `swift test --package-path Packages/CellarCore` — record the total against the **1,870**
      baseline measured at `03be818`.
- [x] 6‴.2 `xcodebuild test … -only-testing:cellarTests` — record **distinct test ids** against the
      **258** baseline measured at `03be818`. Never quote the raw `Test case … passed` line count as an
      id count: parameterized tests print one line per case. **Redirect with `> log 2>&1`, never `tee`**
      — see the round-4 measurement gotcha; a `tee`d log interleaves xcodebuild's status block into a
      `Test case …` line, and a line-based scan then drops that id and under-counts by one. The full
      `-scheme cellar` runner is **not** the gate — it is red on `main` from two pre-existing
      `cellarUITests` Taps failures.
- [x] 6‴.3 Bindings proof — `git diff --stat main --` over `cellar/Browse/BrowseView.swift`,
      `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `PackageSearchIndex.swift`,
      `MutationCommand.swift`, `PackageDetailView.swift` and `cellarUITests/` must print **nothing**.
      `cellar/Browse/PackageRow.swift` and `cellar/Browse/StatusPill.swift` must have a zero diff
      against `03be818`.
- [x] 6‴.4 `git diff --shortstat main...HEAD` — report the measured total under the accepted
      `size:exception`; never trim.
- [x] 6‴.5 Commit apply-progress `docs(sdd): record the m11-tap-search round 4 apply progress`.
