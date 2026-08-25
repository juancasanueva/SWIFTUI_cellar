# Spec index — `m11-tap-search`

**Four** delta files. Hybrid store: these files are canonical; Engram topic `sdd/m11-tap-search/spec` is
the searchable mirror. **Revision 10** — the 2026-08-25 maintainer **UI feedback** that the tap rows
carry the catalog row's **leading icon tile**, on top of revision 9's shared Actions section, revision
8's colliding-hit route, revision 7's name-only detail, revision 6's mutation verbs, revision 5's
update pill, revision 4's install pill and revision 3's scope change.

**UI feedback, 2026-08-25 (round 9, binding, final).** Observed in the running app, comparing the
catalog result rows against this surface's rows: every catalog row and every Installed row opens with a
**leading icon tile** — the formula glyph for a formula, the coloured initial tile for a cask whose
artwork is unavailable — and the tap rows opened with text. The tap rows now draw the **same shared
component**, `PackageIconTile`, with the **same argument shape**, fed by the **same pipeline** the shell
already hands the catalog surface. That component needed **no edit**: its cask branch already answers
the coloured initial tile for a token the artwork registries do not carry, which is exactly a
third-party tap's cask, and its formula branch is unconditional. No artwork load is started by this
surface, so its no-process-layer obligation is untouched. **Scenario counts move by one**:
`package-search` gains one `unit-app` scenario (→ **1 ADDED / 23 scenarios**, 8 req / **42** sc). The
other three capabilities are untouched by round 9.

**UI feedback, 2026-08-25 (round 8, binding).** Observed in the running app, comparing the catalog
detail pane against the two tap-backed panes: the catalog pane presents its verbs as an **Actions**
section at the foot of the pane — a section header, one labelled button per applicable verb, the
primary `brew …` command beneath them with a copy affordance, and the runner-unavailable guidance under
that. The receipt-backed pane (m10, promoted **II15**) and the name-only tap pane (round 6, PS8) both
hung the row's `⋯` menu in the header's primary-button slot instead. Both panes now call **the one
shared Actions section the catalog pane already uses**, in the same position, and both header slots are
empty. The `⋯` menu is **untouched on the list rows**, where it stays the right affordance. The change
is presentational: the entries handed over are unchanged, no verb is added or re-implemented, no argv
shape moves, and no trust presentation is added to either pane (PM10, TM12, PT7). **Scenario counts do
not move at all**: `package-search` amends PS8's pane clause and its pane-composition `unit-app`
scenario in place, and `installed-inventory` gains a **new delta file** whose single MODIFIED **II15**
block amends one clause and one scenario in place. The arithmetic below is therefore unchanged except
for the new capability row, which nets zero.

**Product decision, 2026-08-25 (round 7, binding).** The **collision** half of round 6's ambiguity rule
is reversed. A hit whose bare token the catalog also carries is now **selectable** and opens the
**catalog's own detail**, because Homebrew resolves that bare token to the catalog package — which is
exactly what the row's collision note already says, in those words. Withholding the route left the user
with a sentence naming a package and no way to look at it. The route costs **no new branch**: the
shipped resolution order already resolves the catalog first, so the hit simply becomes routable by its
`PackageID`. The collision note is **unchanged and still required**, the receipt branch and the
inventory branch are untouched, and the **sole** remaining inert row is a **duplicate `PackageID` among
the emitted hits** — two third-party taps publishing one name, neither of them the catalog's — which
nothing can disambiguate. **Scenario counts move by one**: `package-detail` PD6 gains a third `unit`
scenario (→ 8 req / **34** sc) pinning that the record a colliding selection returns is the catalog's
own, byte-identical to the one returned with no tap inventory resident. `package-search` gains
**none** — its two affected `unit` scenarios and its one `unit-app` scenario are amended **in place**,
because each already owned the claim that moved. `tap-management` is untouched by round 7.

**Product decision, 2026-08-25 (round 6, binding).** The 2026-08-24 decision that a not-installed hit is
**non-selectable** is reversed in favour of the follow-up recorded beside it. A not-installed hit whose
identity is **unambiguous** now opens a **minimal detail composed exclusively from the resident tap
inventory** — identity, kind, tap of origin, TM5's shipped `Not installed.` state, the shared mutation
menu, and one new pinned footer. Nothing else: a description, a version, a homepage, a licence, a
dependency list, an analytics figure or a size would all need the tap-source read TM5 forbids, and an
installed package gets those from its receipt instead. **Ambiguity is untouched** — a colliding token or
a duplicate `PackageID` still withholds the route in either install state — and no trust presentation is
added (PM10, TM12). **Scenario counts move by four**: `package-search` gains one `unit` and one
`unit-app` scenario (→ **1 ADDED / 22 scenarios**, 8 req / **41** sc), `package-detail` PD6 gains a
second `unit` scenario (→ 8 req / **33** sc), and `tap-management` TM5 gains a second `unit` scenario
(→ 13 req / **61** sc).

**UI feedback, 2026-08-25 (round 5, binding).** Observed in the running app: the `⋯` menu on an
**installed** tap row offered only Install and Copy install command, where the catalog result surface
offers Reinstall, Uninstall…, Uninstall and Zap… for a cask, and Upgrade and Pin/Unpin where they apply.
The surface handed the shared mutation menu an entry built with **no installed record**, so the menu's own
installed branch could never be taken. The projection now resolves that record — by the same **tap-aware
handoff** the offered version uses, never by a bare identity lookup — and the row hands it over, so the
verbs agree with the pills rounds 3 and 4 put on the same row. No verb is re-implemented, no argv shape is
added, and the affordances stay unconditional with no trust gate. **Scenario counts move by one**: one new
`unit-app` scenario for the composition, with the round-5 `unit` obligations amended into the existing
facts and offered-version scenarios, so `package-search` becomes **1 ADDED / 20 scenarios** (→ 8 req /
**39** sc). `package-detail` and `tap-management` are untouched by round 5.

**UI feedback, 2026-08-25 (round 4, binding).** Round 3 gave the tap rows the catalog row's **Installed**
pill and stopped there. An installed tap package whose own receipt already reports it outdated therefore
reads as merely installed here while the same package reads as updatable on the catalog surface and in
the Installed list. The tap rows now carry the **same shared UPDATE pill**, in the same position — after
the Installed pill — fed by an offered version the projection derives from the **installed receipt it
already holds**. No brew invocation is added. **Scenario counts move by two**: one `unit` scenario for the
fact and one `unit-app` scenario for the shared component, so `package-search` becomes **1 ADDED / 19
scenarios** (→ 8 req / **38** sc). `package-detail` and `tap-management` are untouched by round 4.

**UI feedback, 2026-08-25 (round 3, binding).** Observed in the running app: a tap row carried a third
text line reading `Installed.` or `Not installed.`, where a catalog row carries a green **Installed**
pill and shows nothing at all when the package is not installed. The tap rows now mirror the catalog
rows — the **same shared pill component**, no state sentence — so one install state is presented one
way on both search surfaces. Both strings are **withdrawn** as this surface's copy; the withheld state
keeps TM5's sentence *and* gains the pill; the collision note is unchanged. **Scenario counts do not
move**: the change lands as amended clauses in PS8 plus amended bullets inside two of its existing
scenarios, so the arithmetic below stands exactly as revision 3 recorded it.

**Scope change, 2026-08-25 (binding).** The tap packages get their **own surface**, not a section
inside Browse. Browse — "Search catalog" — stays **catalog-only**, and `cellar/Browse/BrowseView.swift`
carries a **zero-line diff**, asserted. The new surface is its own sidebar entry titled
`Search our taps`, laid out as a visual copy of Browse. What changed with it: an **empty query lists
everything the installed taps publish** (mirroring PS5) instead of yielding nothing; the surface has
**no Outdated control**, so that rule is gone rather than restated; an unavailable inventory renders an
**ordinary empty state with pinned copy** instead of an absent section; and the latency requirement is
restated **per surface** rather than as a shared keystroke turn. The string `From your taps` is
**withdrawn** — it named a section that no longer exists.

| Capability | Op | Block | Scenarios | Net |
|---|---|---|---|---|
| `package-search` | **ADDED** — packages published by installed third-party taps are searchable as a composed source | new, promotes as **PS8** | +23 (14 `unit`, 9 `unit-app`) | 7 → **8** requirements, 19 → **42** scenarios |
| `package-detail` | **MODIFIED** — **PD6** | whole block, all three existing scenarios byte-identical | +3 (`unit`) | 8 requirements unchanged, 31 → **34** scenarios |
| `tap-management` | **MODIFIED** — **TM5** and **TM11** (main-spec markers) | both whole blocks, all 12 existing scenarios byte-identical | +3 (`unit`) | 13 requirements unchanged, 58 → **61** scenarios |
| `installed-inventory` | **MODIFIED** — **II15** (round 8) | whole block, 11 of its 12 existing scenarios byte-identical, the twelfth amended in place | **+0** | 15 requirements unchanged, 79 → **79** scenarios |

**Totals: 1 ADDED, 4 MODIFIED blocks across 3 capabilities, 0 REMOVED, 0 RENAMED — 29 new scenarios
(20 `unit`, 9 `unit-app`).** No requirement is removed or renamed, so `rules.archive`'s
destructive-delta warning does not fire. The `installed-inventory` row contributes **no** new scenario
by design: round 8 changes how II15's verbs are *presented*, and the scenario that owned that claim is
amended rather than joined by a second one that would restate it.

> **Arithmetic correction, round 5.** This line read “20 new scenarios (15 `unit`, 5 `unit-app`)” from
> revision 3 onward and was not re-footed when rounds 3 and 4 amended the table above it. The table is
> and was authoritative: 20 + 1 + 2 = **23**, of which 13 + 1 + 2 = **16** are `unit` and **7** are
> `unit-app`. The row totals are unchanged by this correction; only this summary is.

**One catalog read is permitted, and only one.** PD6's added paragraph allows the composed surface to
read the catalog for **membership alone** — whether a hit's bare token is also carried by the catalog
for the same kind — because that is what produces the collision fact the row's note is worded from.
Since round 7 that read decides **nothing else**: it no longer feeds routability, which is now
uniqueness among the emitted hits and nothing more. The read still creates no catalog record, adds
nothing to the snapshot or the index, and draws no catalog value into the hit beyond the collision
itself. PS8 declares the same membership answer as an input of the projection, used for that fact and
for nothing else. PD6's round-7 sentence adds no second read: it describes the **ordinary** detail
lookup answering, for a package the catalog already covers, when such a row is selected.

## Verification classes

Both names are already established in this repository; this change introduces none.

| Class | Meaning | Runner |
|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` | `swift test --package-path Packages/CellarCore` |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom that reads the repository source off disk — the established class for app-target composition and source-scan assertions (`openspec/specs/app-updates/spec.md:17`) | `xcodebuild test … -only-testing:cellarTests` |

None of the three target specs carries a `## Verification classes` table today (only `app-updates` and
`release-distribution` do), so **no class table is promoted at archive**. Each delta's table is
delta-local provenance; the per-scenario inline `- Verification:` lines promote with their
requirements, following the precedent `2026-08-23-m7-tap-trust` recorded at
`openspec/specs/installed-inventory/spec.md:1122-1184`.

## Copy pinned by these deltas

| Fact | Exact copy | Condition |
|---|---|---|
| Surface title and sidebar entry | `Search our taps` | always — both the section-list entry and the surface's own title. **New copy**, replacing the withdrawn `From your taps` |
| Empty state — inventory unavailable | `No packages from your taps.` | `brewAbsent` or a failed refresh; an ordinary empty state, never an error. **New copy** |
| Empty state — nothing published | `Your taps publish nothing yet.` | inventory available, no installed third-party tap publishes anything. **New copy** |
| Catalog collision note | `Also in the catalog. Homebrew installs the catalog package.` | the hit's bare token is also carried by the catalog for the same kind; supplied by the projection, never composed by the surface. **Round 7**: unchanged and still required — the row it sits on is now also **selectable**, and it opens the very package this sentence names, so the note and the route agree rather than compete |
| Install state — installed | ~~`Installed.`~~ — **WITHDRAWN 2026-08-25 (round 3)** | Replaced by the **shared status pill** the catalog result surface already draws, reading `Installed`. Not copy this delta owns: the label lives in that one shared component, so neither search surface and no projection composes it |
| Install state — tap withheld | `Installed. Homebrew withholds its tap while this tap is untrusted.` | TM5's exact shipped string, reused byte-for-byte. **Round 3**: the withheld row now carries the pill **and** this sentence — it is installed, and the sentence explains what Homebrew is withholding |
| Install state — not installed | ~~`Not installed.`~~ — **WITHDRAWN 2026-08-25 (round 3)** | A not-installed row carries **no state copy and no pill**, exactly as the catalog result surface shows nothing for a row that is not installed |
| Update available — installed and outdated | **no copy pinned here** — the **shared update pill** the catalog result surface and the Installed list already draw | **Round 4**: an installed hit whose receipt reports it outdated carries that pill, after the Installed pill, fed the **offered version as a value**. Not copy this delta owns: the label and the wording around the version live in that one shared component, so neither search surface and no projection composes them |
| Mutation verbs on an installed row | **no copy pinned here** — Reinstall, Uninstall…, Uninstall and Zap…, Upgrade, Pin and Unpin belong to the **shared mutation menu** | **Round 5**: the row hands that menu the hit's installed record, so an installed hit takes the menu's installed branch. Not copy this delta owns and not verbs it declares: every label, every argv and every applicability rule lives in the shared menu and the shipped command type, and the surface supplies only the record and the bare target they already take |
| Name-only detail — install state | `Not installed.` | **Round 6**: on the **detail pane** for an unambiguous not-installed hit, reusing TM5's exact shipped string byte-for-byte. The round-3 withdrawal above is about the **row**, where a pill answers instead; a pane with no pill has to say it. Supplied by the projection, never composed by the pane |
| Name-only detail — footer | `Cellar knows this package by name only until it is installed.` | **Round 6**: always, on that pane. **New copy** with no shipped precedent, supplied by the projection like every other sentence this change pins, so it is worded in exactly one place and appears nowhere in the application's own sources. It states the pane's own boundary — why there is no description, no version and no size — without claiming anything about the package or its tap |
| Name-only detail — collision note | **none** — the note is **not** rendered on this pane, and its absence is asserted | **Round 6**: a colliding bare token is carried by the catalog, so the catalog detail resolves it before this branch and the row offering it is unroutable for the same reason. A note here could never be reached, and unreachable presentation is worse than none. **Round 7**: the row is now routable, so the **branch ordering** is the sole guarantee — and it is sufficient, because that ordering is itself asserted |

Both withdrawn strings stay **unchanged in TM5** for the tap-detail rows TM5 governs; only this
surface's **row** copy is withdrawn — and round 6 puts `Not installed.` back on the **pane**, where no
pill carries the fact, again as TM5's exact string rather than a reworded one. Neither is promoted by this change, and no MODIFIED block is needed to
withdraw them: PS8 is an ADDED requirement that reaches `openspec/specs/**` for the first time at
archive, so it simply lands without them.

The withheld-state and collision strings MUST be produced by the **projection**, never composed by
the presenting surface; the surface title and the two empty-state strings belong to the surface and its
section-list entry. TM5's withheld string is reused rather than reworded so the same install state
cannot read differently on Taps and on the tap query surface. The collision note is a neutral statement
of Homebrew's own resolution: no recommendation, no warning styling, and no suggestion to
disambiguate — because PM10 forbids qualifying the argv, so there is nothing for the user to act on
beyond knowing which package brew will install. A non-empty query that matches nothing reuses the
ordinary no-match empty state the catalog query surface already has; no copy is pinned for it.

## Presentation decisions consumed

Maintainer/orchestrator, 2026-08-24, Engram `sdd/m11-tap-search/state` obs `#7795`, all binding and all
carried into PS8:

| Decision | Where it lands in PS8 |
|---|---|
| ~~Section renders **below** the catalog rows~~ — **superseded 2026-08-25** | Its own surface titled `Search our taps`, never interleaved with catalog results, with Browse untouched: presentation paragraph + `unit-app` surface-title scenario + `unit-app` untouched-catalog-surface scenario |
| Collision shown with a neutral note, never suppressed | collision paragraph + `unit` collision scenario |
| Tap name only — no `Untrusted` badge, no trust control | install paragraph + `unit-app` no-trust-gate scan |
| ~~Not-installed rows non-selectable~~; installed hits route to the m10 receipt pane — **half superseded 2026-08-25 (round 6)**, see the round-6 and round-7 rows below | install-state paragraph + both routing scenarios. **Refined by the orchestrator gate**: an installed hit whose identity is ambiguous — colliding bare token, or two emitted hits sharing a `PackageID` — is also non-routable, because the catalog-first resolution would open a different package; it stays presented and installable (`unit` ambiguity scenario). **Half of that refinement is reversed in round 7**: the colliding case now routes, precisely *through* the catalog-first resolution, to the package the row's note names; only the shared-`PackageID` case stays inert |
| ~~Section renders only for a non-empty query~~ — **superseded 2026-08-25** | An empty query lists everything the installed taps publish, in the deterministic order, mirroring PS5: empty-query paragraph + `unit` list-everything scenario |
| "Hide installed" subtracts from the tap results | filters paragraph + `unit` hide-installed scenario |
| ~~Outdated hides the section entirely~~ — **superseded 2026-08-25** | The surface offers **no** outdated control at all (a tap hit has no version, and II8 forbids an enabled control that cannot change results): filters paragraph + the same `unit` scenario's enumeration clause |
| Prompt count stays catalog-only | filters paragraph — Browse's prompt is unchanged, and the tap surface's own prompt claims no catalog count |
| Matching via the index's normalisation, exact/prefix/substring ladder | matching paragraphs + three `unit` scenarios (ladder, token-awareness, total order). **Refined by the orchestrator gate**: the ladder is token-aware (`gentle-ai` → tokens `gentle ai`, so `ai` is an exact-token match), matching applies to the published qualified name as well as the bare token, and a qualified-name-only match ranks no higher than substring |
| ~~Section absent, never an error, when the tap inventory is unavailable~~ — **superseded 2026-08-25** | An ordinary empty state with pinned copy, never an error, distinguishing an unavailable inventory from an empty one: availability paragraph + `unit` empty-state scenario |
| PS6's ceiling not regressed; no new brew invocation | latency paragraph + `unit` per-surface latency scenario + `unit-app` process-layer scan. **Restated 2026-08-25**: the surfaces answer separate keystroke turns, so the tap surface holds the same 8 ms p95 ceiling on its own turn and PS6's catalog measurement is unchanged |
| ~~Install state shown as a row sentence: `Installed.` / `Not installed.`~~ — **superseded 2026-08-25 (round 3)** | The **shared `Installed` pill** the catalog row already draws, on both installed states, and **nothing** on a not-installed row: install-state paragraph + the `unit` install-state scenario + the `unit-app` copy-ownership scan. The withheld sentence survives as the row's explanatory line, beside the pill |
| An available update is marked with the **shared UPDATE pill**, after the Installed pill — **added 2026-08-25 (round 4)** | The offered version becomes a **sixth fact** of the hit, derived from the installed receipt and gated on its own `isOutdated`: six-facts paragraph + offered-version paragraph + update-pill paragraph, the new `unit` offered-version scenario and the new `unit-app` shared-update-pill scenario. The **Outdated control stays absent** — its rule survives round 4 with a narrowed reason, stated in the filters paragraph |
| An installed row offers the **same verbs the Installed and catalog surfaces offer** — **added 2026-08-25 (round 5)** | The hit gains a **mutation handoff** — this machine's own installed receipt, resolved by the tap-aware handoff, present in both installed states and absent when not installed — and the row hands it to the shared mutation menu: verbs paragraph + handoff paragraph, the amended facts and offered-version `unit` scenarios and the new `unit-app` mutation-composition scenario. It is **not a seventh fact**: it publishes nothing the tap declares, costs no brew invocation, and the surface presents nothing from it |
| ~~Not-installed rows non-selectable~~ — **reversed 2026-08-25 (round 6)** | An unambiguous not-installed hit **is** selectable and opens a minimal detail composed exclusively from the resident tap inventory — identity, kind, tap of origin, TM5's `Not installed.`, the shared mutation menu and one pinned footer, and nothing that would need a tap-source read: selectability paragraph + detail paragraphs, the amended ambiguity `unit` scenario and surface-entry `unit-app` scenario, the new `unit` resolution scenario and the new `unit-app` composition scenario. **Ambiguity still withholds the route** in either install state, and no trust presentation is added |
| ~~A colliding hit is non-selectable~~ — **reversed 2026-08-25 (round 7)** | A colliding hit **is** selectable and opens the **catalog's own detail** — the package Homebrew resolves its bare token to, and the one its own collision note names. Routability becomes **uniqueness among the emitted hits** and nothing else: rewritten selectability clause + the colliding-route paragraph, the amended collision `unit` scenario, the amended ambiguity `unit` scenario (now duplicate-only) and the amended surface-entry `unit-app` scenario, plus PD6's new `unit` scenario. **No routing branch is added** — the shipped catalog-first order already answers — the collision note is unchanged and still required, and the receipt and inventory branches are untouched. The **only** inert row left is a duplicate `PackageID` among emitted hits |
| ~~The tap-backed panes offer their verbs through the row's `⋯` menu, in the header's primary slot~~ — **reversed 2026-08-25 (round 8)** | Both tap-backed detail panes — the receipt-backed one **II15** owns and the name-only one PS8 added — present the **same Actions section the catalog detail pane presents**, from **one** shared component, placed **last** in the pane, with the primary `brew …` command line and its copy affordance; both header primary slots are **empty**. The `⋯` menu is **unchanged on the list rows**. Lands as PS8's rewritten pane clause + its amended `unit-app` pane-composition scenario, and as a **new `installed-inventory` delta** whose MODIFIED **II15** amends the verb clause and the verb scenario in place. **No scenario is added**, no verb is re-implemented, no argv shape moves, and no trust presentation appears on either pane |
| ~~The tap rows open with the package name~~ — **added 2026-08-25 (round 9, final)** | Every tap row opens with the **same leading icon tile the catalog result row and the Installed row open with**, from **one** shared component and with the **same argument shape** — the formula glyph for a formula, the cask artwork where it exists and the coloured initial tile where it does not, which for a third-party tap's cask is the ordinary case. The artwork dependencies are optional properties of the surface, filled at its one call site by the shell that already fills the catalog surface's. Lands as PS8's new tile clause + one new `unit-app` scenario. The shared component is **unedited** — its fallback already answered correctly for a token no registry carries — **no** load, refresh or asynchronous work joins this surface, and no trust presentation appears on the row |

## `package-mutation`: activated, not changed — no delta

m11 adds **no** `package-mutation` delta. PM10 (`openspec/specs/package-mutation/spec.md:619-768` —
the whole requirement block; the clauses cited below are its prohibition paragraphs and scenarios)
binds the new install path exactly as written today and is **activated** by it:

| PM10 clause | How m11 activates it |
|---|---|
| No argv on the shared mutation spine carries a `/`-qualified package token (`:647-652`, scenario `:713-719`) | The tap hit's mutation target is the bare `PackageID` the tap projection already produces, so the install is the **existing** family with the **existing** argv shape. The enumeration gains no family and needs no edit — including for a colliding hit, where qualifying to disambiguate is exactly what the clause forbids. |
| The refusal MUST NOT become a pre-launch gate (`:659-662`) | Install is offered unconditionally for every hit; brew decides. PS8 restates the prohibition for this surface as an absence and asserts it by source scan. |
| The same prohibition holds for per-package grant state (`:664-670`) | The composed source reads no trust report, store or projection at all. |
| Enforced structurally by the shipped source-scanning assertion (`:672-676`) | The new projection and the new surface are added to what that idiom covers; PS8's `unit-app` scenario is the assertion. |
| Typed refusal copy and Trust recovery (`:640-645`, `:705-711`) | Unchanged and reused end to end: an untrusted tap surfaces through the shipped refusal, not a Cellar-side block. |

A `package-mutation` MODIFIED block would restate a requirement that already says the right thing, so
`sdd-spec` found **no genuine gap** and wrote none. Record this at archive as *activated, not changed*.

## `installed-inventory`: activated by II7 and II8, and **modified** at II15 in round 8

Rounds 1–7 recorded this capability as *activated, not changed*. **Round 8 changes that for II15 only**,
and the delta says so in `specs/installed-inventory/spec.md`: II15's mutation-verb clause pinned the
verbs to "the same shared mutation surface" the installed **list row** uses, and its verb scenario
pinned that shape, so presenting them as the catalog pane's **Actions** section would have contradicted
a promoted requirement rather than merely re-styling a pane. II7 and II8 below are **still** activated
rather than changed.

| Requirement | How m11 activates it |
|---|---|
| **II7** — the catalog target does not depend on the brew-process target | The projection lives in `BrewClient`, which already imports `Catalog`; the direction is unchanged, which is precisely why index ingestion (explore Approach C) was rejected. |
| **II8** — installed-state filters are composed, never pushed into the search index | PS8 extends the same discipline to a second result source: the hide-installed subtraction composes above it, and II8's "no enabled control that cannot change the visible results" rule is why the tap surface offers no outdated control at all. |
| **II15** — the installed receipt supplies a reduced detail for a package the catalog does not carry | An installed tap hit routes there by exact `PackageID` through the existing resolution order; no routing branch is added. **Round 8: no longer activation alone** — its mutation-verb clause and its verb scenario are MODIFIED so that pane presents the catalog pane's Actions section instead of the list row's `⋯` menu. See the delta file. |

## Numbering and marker drift, recorded once

- `openspec/specs/package-search/spec.md` and `openspec/specs/package-detail/spec.md` carry **no
  `<!-- PS# -->` / `<!-- PD# -->` markers** — `tap-management` is the only spec that uses marker
  comments. PS8 and PD6 are ordinal labels used in prose; the blocks are matched by heading.
- `explore.md` and `proposal.md` call the tap-management adjacent-capabilities requirement **TM10** and
  the trust-presentation requirement **TM11**. The file's markers are **`<!-- TM11 -->`** (`:532`) and
  **`<!-- TM12 -->`** (`:560`). These deltas use the file's markers. "TM11 untouched" in the decision
  record means the main spec's **TM12** — and it is untouched.

## Excluded from these deltas, deliberately

- **Any tap-source read**, and therefore any description, version, homepage, license, dependency list,
  install count, deprecation flag or size for a not-installed tap hit. TM5 forbids the read
  unconditionally, and PS8 restates the resulting **six-fact** ceiling (round 4 raised it from five by
  adding the offered version, which comes from this machine's own receipt rather than from the tap;
  round 5 adds a receipt **handoff**, which is not a fact and does not raise it again).
- **A merged ranked list.** PS3's order is broken by 365-day install count, which a tap package does
  not have. The two orders stay independent, which is also what keeps the hits visibly a different kind
  of result rather than degraded catalog rows.
- ~~**A name-only detail pane for a not-installed hit.** Not-installed rows are non-selectable in this
  slice; the minimal pane is a clearly scoped follow-up.~~ — **no longer excluded: delivered in round
  6.** The exclusion was written when the route was withheld; the maintainer reversed that and the pane
  is in this change. Recorded here rather than deleted, because the exclusion list is the record of what
  each slice deliberately left out and why it stopped being true. (Missed when round 6 landed; corrected
  in round 7.)
- **Any `SearchFilters` member for this source.** PS4's declared-filter-set scenario stays true by
  construction: this source is composed, not filtered.
- **A `package-trust` delta.** Nothing on this surface reads, presents or decides on a grant.
- **Any change to Browse.** `cellar/Browse/BrowseView.swift` carries a zero-line diff, asserted by a
  `unit-app` scenario that also scans it for any reference to the tap search projection or its view.
  Browse's prompt, filter bar, row identity and selection plumbing are all untouched, which retires
  proposal risk R4 (sectioned-list regression) outright.
- **An Outdated control on the tap surface.** A tap hit carries no version, so the control could never
  change what is visible — II8 forbids exactly that.
