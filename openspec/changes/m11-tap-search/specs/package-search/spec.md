# Delta for package-search

Existing capability — `openspec/specs/package-search/spec.md` (**7 requirements / 19 scenarios**,
established by `2026-08-01-m1-catalog-browse` and extended by `2026-08-02-m2-catalog-hardening`). This
delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**: **22 scenarios** are added, taking the
capability to **8 requirements / 41 scenarios**.

Nothing is removed, modified or renamed here, so `rules.archive`'s destructive-delta warning does not
fire and PS1–PS7 stay byte-identical. In particular the index keeps its identity rule, its
normalisation, its ranking order, its declared filter set, its measured ceiling and its off-main
build: this requirement adds a **second source composed above the index**, never a second source
inside it.

**Why ADDED and why here.** `package-search` owns the query surface, so it owns the answer to "the
package I searched for is not in the catalog, and Cellar already has its name in memory". The
composition discipline is not new: `installed-inventory` II8 already requires installed, not-installed
and outdated state to be *composed* against catalog results rather than pushed into the index, and
`InstalledBrowse` is the shipped precedent. This requirement extends the same discipline to a second
result source without touching the index contract PS1–PS7 states.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m11-tap-search/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**Binding decisions consumed** (maintainer/orchestrator, 2026-08-24, Engram
`sdd/m11-tap-search/state` obs `#7795`): Approach A; the collision note is a neutral statement of
Homebrew's resolution with no nudge; the row shows the tap name only and no trust badge; "Hide
installed" subtracts from the tap results; a not-installed hit is non-selectable and an installed hit
routes to the m10 receipt pane.

**Maintainer scope change, 2026-08-25 — binding, and this revision's reason.** The tap packages get
their **own surface**, not a section inside Browse. Browse stays **catalog-only** and its file carries
a **zero-line diff**. The new surface is its own sidebar entry titled “Search our taps”, laid out as a
visual copy of Browse. Three behaviours changed with it: an **empty query lists every published
package** (mirroring PS5 for the catalog) instead of yielding nothing; there is **no Outdated
control** on the surface, so the outdated-hides-everything rule is gone rather than restated; and an
unavailable tap inventory renders an **ordinary empty state with pinned copy** rather than an absent
section. The string “From your taps” is withdrawn — it named a section that no longer exists.

**Maintainer UI feedback, 2026-08-25 (round 3) — binding, and this revision's reason.** Observed in the
running app: the tap rows carried a third text line reading “Installed.” or “Not installed.”, where the
catalog rows carry a green **Installed** pill and nothing at all when a package is not installed. The
tap rows now mirror the catalog rows exactly — the **same shared pill component**, and no state
sentence — so the two search surfaces present one install state one way. The strings “Installed.” and
“Not installed.” are **withdrawn** as this surface's copy. The withheld state keeps TM5's sentence as
its explanatory line **and** gains the pill, because it *is* installed; the collision note is unchanged.

**Maintainer UI feedback, 2026-08-25 (round 4) — binding, and this revision's reason.** Round 3 gave the
tap rows the catalog row's **Installed** pill; it did not give them the catalog row's **UPDATE** pill. An
installed tap package whose own receipt already reports it outdated therefore reads as merely installed
on this surface while the same package reads as updatable on the catalog surface and in the Installed
list — the second half of exactly the drift round 3 closed. The offered version is **already resident**:
the projection holds the installed inventory, and that receipt carries both the outdated flag and the
version brew currently offers, so nothing new is read and no brew invocation is added. Round 4 makes the
offered version a **fact of the hit**, gated on the receipt's own outdated rule, and marks the row with
the **same shared update pill** the catalog surface and the Installed list already draw.

**Maintainer UI feedback, 2026-08-25 (round 5) — binding, and this revision's reason.** Observed in the
running app: the row's `⋯` menu on an **installed** tap package offered only Install and Copy install
command, while the catalog result surface offers Reinstall, Uninstall…, Uninstall and Zap… for a cask,
and Upgrade and Pin/Unpin where they apply. The cause is a presentation one, not a verb one: the surface
handed the shared mutation menu an entry built with **no installed record at all**, so the menu's own
installed branch could never be taken. Rounds 3 and 4 marked the installed state and the available update
on the row; round 5 makes the **verbs** agree with those marks. Nothing new is read — the receipt is
already resident in the same installed inventory the offered version comes from — no verb is
re-implemented, and the affordances stay unconditional with no trust gate (`package-mutation` PM10).

**Maintainer product decision, 2026-08-25 (round 6) — binding, and this revision's reason.** The
2026-08-24 decision that a not-installed hit is **non-selectable** is **reversed** in favour of the
follow-up recorded beside it. A not-installed hit whose identity is **unambiguous** is now selectable
and opens a **minimal, inventory-fed detail**: the identity the inventory publishes, the kind, the tap
of origin, the install state, the shared mutation menu, and a footer saying plainly that Cellar knows
this package by name only. Round 1's reason for withholding the route — “there is nothing honest to
present” — was a claim about a *catalog* pane and a *tap-source* read, and both remain forbidden. What
this round establishes is that the four names the resident inventory already publishes **are** honest
to present, on exactly the terms `package-detail` PD6 and `tap-management` TM5 already grant the
receipt-backed pane. **Ambiguity is untouched**: a colliding token or a duplicate `PackageID` still
withholds the route in **either** install state, because the catalog-first resolution would open a
different package than the row chosen. Nothing about tap-source reads, catalog records or trust
presentation is weakened; the pane adds none of the three.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` ("observable behavior of CellarCore types without referencing SwiftUI views") | `swift test --package-path Packages/CellarCore` | **14** |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom that reads the repository source off disk — the established class for app-target composition and source-scan assertions (`openspec/specs/app-updates/spec.md:17`) | `xcodebuild test … -only-testing:cellarTests` | **8** |

## ADDED Requirements

### Requirement: Packages published by installed third-party taps are searchable as a composed source

A package published by an installed third-party tap MUST be findable by query, on **its own surface**,
distinct from catalog search and **never interleaved with catalog results**. That source MUST be
**composed above the search index and never pushed into it**, on exactly the discipline
`installed-inventory` II8 already applies to installed state. The index's identity rule, its
normalisation, its ranking order, its declared filter set, its build and its results MUST be
unchanged, and no tap package MUST enter the catalog snapshot, the index or any catalog result
(`package-detail` PD6, `tap-management` TM5).

The composed source MUST be fed **exclusively by the tap inventory already resident** from the refresh
`tap-management` performs, and MUST cost **no brew invocation**: composing, ranking, filtering or
presenting it MUST NOT spawn a process, MUST NOT start or await a refresh, and MUST NOT read a tap's
formula or cask source. It MUST be answered by a pure, `nonisolated`, `Sendable` projection over that
tap inventory, the installed inventory, the query, the query's kind filter, and a **catalog membership
answer used solely for the collision fact below** — never for a hit's content — so the whole rule is
observable with no process launcher to inject.

A hit MUST carry exactly six facts: the package **kind**, the **bare token** brew installs by, the
**published qualified name** the tap declares, the **tap of origin**, its **install state**, and the
**offered version** where — and only where — this machine's own installed receipt reports the package
outdated — together with the **projection-supplied explanatory copy** for that install state where any
is pinned (the withheld state alone, below), and the collision note where the hit collides. It MUST
carry nothing else — in particular no description, no **published** version, no homepage, no
license, no dependency list, no install count, no deprecation flag, no disabled flag and no size —
because the tap inventory publishes none of them and obtaining any of them would require the
tap-source read TM5 forbids. An absent fact MUST be absent rather than an empty string, a dash,
`unknown` or any other placeholder.

Round 5 adds one member that is **not** a seventh fact: the **installed receipt this machine already
holds** for the hit, present for an installed hit in **either** installed state and absent for a
not-installed one. It is a **mutation handoff**, carried so the shared mutation spine below can be
handed the record it already requires, and it MUST be resolved by the **same tap-aware handoff** the
offered version is resolved by — never by a bare `PackageID` lookup, which answers for a receipt whose
tap names a different tap and would attach a colliding catalog package's record to a tap row. It
therefore changes none of the prohibitions above: it introduces no tap-published value, costs no brew
invocation, and the surface MUST present nothing from it beyond the shared components this requirement
already names. The six facts remain six, and the offered version MUST continue to be derived from that
same receipt under the receipt's own outdated rule rather than re-derived beside it.

The offered version is **not** an exception to that prohibition: it is not read from the tap, from the
tap's source or from the catalog. It is read from the **installed receipt this machine already holds**,
which is the same inventory the install state is resolved against, so it costs no brew invocation and is
representable only for a package this machine has. It MUST be absent for every **not-installed** hit,
and absent for an installed hit whose receipt does **not** report it outdated, by the receipt's **own**
outdated rule — the one `installed-inventory` II4 already defines, including the self-updating-cask
exclusion — so this surface can never disagree with the Installed list about which packages have an
update.

Matching MUST use the **same normalisation the index uses** (PS2) and MUST be applied to **both** the
bare token and the published qualified name, so a query naming a tap — `gentleman`, say — surfaces
that tap's packages rather than nothing. It MUST be ranked by a ladder of **exact**, then **prefix**,
then **substring** match; a hit MUST be ranked by its strongest class only, and there is no
description to scan, so the ladder MUST stop there rather than inventing a fourth class.

The ladder MUST be **token-aware**, because the shared normalisation collapses `-` and every other
non-alphanumeric run into a separator: `gentle-ai` normalises to the two tokens `gentle ai`. **Exact**
therefore means the normalised query equals the whole normalised string **or** a whole normalised
token of it, and **prefix** includes a prefix of any normalised token, not only of the whole string.

A match found **only** in the published qualified name MUST rank no higher than **substring**, because
that name carries the tap's own owner and repo: promoting it would let a tap name outrank a package
whose bare token actually begins with the query. A hit whose **bare token** matches exactly or by
prefix MUST keep that stronger class.

Within a class the order MUST be normalised bare token ascending, then `formula` before `cask`, then
tap name ascending, so the order is **total and reproducible**. Tap hits MUST NOT be interleaved into
the catalog's ranked order: PS3's order is defined over catalog records and broken by 365-day install
count, which a tap package does not have, so the two orders MUST remain independent.

An **empty or whitespace-only query MUST list every package published by every installed third-party
tap**, in the deterministic order below, exactly as PS5 makes an empty catalog query return the whole
filtered catalog. It MUST NOT return an error, MUST NOT return zero results while packages are
published, and MUST NOT throw. A query that matches nothing MUST return an empty result set, again as
PS5 requires of the catalog.

Where the tap inventory is unavailable — brew absent, or its refresh failed — the surface MUST present
an **ordinary empty state and never an error**: no error banner, no failure copy, no retry demand, and
no claim that something went wrong. That state MUST carry the exact copy “No packages from your
taps.”. Where the inventory is available but no installed third-party tap publishes anything, the
surface MUST carry the exact copy “Your taps publish nothing yet.”, so an unavailable inventory and an
empty one are not presented as the same fact. A non-empty query that matches nothing MUST use the same
ordinary no-match empty state the catalog query surface already uses; no new copy is pinned for it.
Neither state MUST change a catalog result, and catalog search MUST remain fully usable while the tap
inventory is unavailable.

The query's declared **kind** filter MUST restrict this source exactly as it restricts catalog results,
and the declared filter set MUST NOT gain a member (PS4). Installed-state controls MUST be composed
above this source on II8's terms: a hide-installed subtraction MUST remove its installed hits exactly
as it removes installed catalog rows. The surface MUST offer **no outdated control**. Round 4 narrows
that rule's reason without weakening the rule: the offered version is now representable, but only for a
hit this machine has installed **and** whose receipt reports it outdated — a strict minority of what the
surface lists — while every not-installed hit still has no version and no outdated state to be filtered
by. An Outdated chip here would therefore not filter the listing so much as **replace** it, silently
collapsing every published package this machine does not have; and the catalog's own chip is defined
over published versions, which this source still does not read. A control whose enabled state does not
answer the question its label asks is what II8 forbids. The surface's own prompt MUST NOT present a
catalog record count, and the
catalog query surface's prompt MUST continue to count **catalog records only** — this source changes
neither.

A tap hit's **row identity** MUST be distinct from any catalog row's identity, formed from the tap of
origin, the kind and the bare token, so two rows for the same `(kind, name)` remain separately
addressable. `PackageID` MUST remain the **mutation target** and MUST NOT be reused as the row
identity. Where a hit's bare token is also carried by the catalog for the same kind, the hit MUST be
**presented, never suppressed**, and MUST report the collision as a fact of the hit. That fact MUST be
presented with the exact copy “Also in the catalog. Homebrew installs the catalog package.” — a
neutral statement of Homebrew's own resolution, carrying no recommendation, no warning styling and no
suggestion to disambiguate. It MUST be supplied by the same projection that answers the source, so the
presenting surface composes none of that copy locally.

Mutation MUST be offered on the **shared mutation spine, unconditionally**, with the existing
bare-token argv. No new command family and no new argv shape MUST be introduced, and the mutation
target MUST remain the bare `PackageID` even for a colliding hit: qualifying the token to disambiguate
is forbidden by `package-mutation` PM10, whose prohibition binds every path on that spine.

The surface MUST hand that spine the **installed record for an installed hit** — in **both** installed
states, resolved by the tap-aware handoff above — and **no record for a not-installed hit**, so the
menu offers exactly what it offers on the Installed and catalog surfaces for the same package: the
install-time affordances for a package this machine does not have, and the installed-time ones —
Reinstall and Uninstall…, Uninstall and Zap… for a cask, Upgrade where the receipt reports the package
outdated, and Pin or Unpin where the receipt makes them applicable — for a package it does. An
installed tap row offering only an install is the same fact answered twice, differently, that II8 and
PT5 forbid: the row already draws the shared **Installed** pill, and where the receipt reports it
outdated the shared **update** pill, so a menu that denies both is contradicted by the row it sits on.

The surface MUST NOT re-implement, re-word, re-order or extend any of those verbs, MUST NOT construct a
mutation command, an argv or a mutation target of its own, and MUST NOT decide which of them applies:
every one of those decisions belongs to the shared menu and the shipped command type, and this surface
supplies only the record and the bare target they already take. The affordances stay **unconditional**
— no trust gate on either granularity, no pre-launch block, no trust badge and no trust control
(PM10) — and the record supplies **no catalog record**: a colliding hit still hands the spine the tap
row's own receipt and never the catalog package's (`package-detail` PD6). This
surface MUST NOT block, disable, hide, delay or pre-qualify the install — or any other affordance —
on a tap's trust state or on per-package grant state, and MUST NOT read a trust report, store or
projection to decide anything before launch (PM10). It MUST present no trust badge and no trust
control, so `tap-management`'s one-projection trust presentation gains no consumer. An untrusted tap
MUST surface through the already-shipped typed refusal and its Trust recovery, never through a
pre-launch block.

The install state MUST resolve into the **same three distinct states** TM5 defines and MUST NOT be
collapsed into two, and the projection MUST expose it as a **fact of the hit** — a value a test can read
directly — rather than as a sentence the row prints.

An **installed** hit, in **either** installed state, MUST be marked by the **same status pill the
catalog result surface already draws for an installed row**, reading exactly “Installed”. That pill MUST
be **one shared component** referenced by both surfaces, never a second pill declared beside it and
never a label either surface composes for itself. `installed-inventory` II8 already requires installed
state to be composed once and presented once, and `package-trust` PT5 already requires one projection to
answer one fact for every surface that shows it; two independently-worded install marks on the
application's two search surfaces is exactly the drift those rules exist to forbid. The label therefore
belongs to that shared component — neither presenting surface composes it, and neither does the
projection.

An installed hit whose **offered version** is present MUST additionally be marked by the **same update
pill the catalog result surface and the installed list already draw for an outdated row**, positioned
**after** the installed pill exactly as the catalog row positions it. That pill MUST be **one shared
component** referenced by every surface that draws it, never a second pill declared beside it and never a
label a presenting surface composes for itself; the offered version MUST be handed to that component as
a **value**, so the component alone words what it says about it. The same II8 and PT5 rules that forbid
two install marks forbid two update marks: “this package has an update” is one fact, answered once, and a
tap row that stays silent about an update the Installed list is already reporting is that fact answered
twice, differently. A hit with **no** offered version MUST carry no update pill — the fact's absence is
its own presentation, exactly as a not-installed row's absent installed pill is.

The **withheld** state MUST carry that same pill **and, in addition**, the exact sentence “Installed.
Homebrew withholds its tap while this tap is untrusted.” — TM5's exact string, scoped to the tap and
never implying the package is untrusted. That sentence is explanatory copy, not a state label: it MUST
be **supplied by the projection**, never composed by the presenting surface, exactly as the collision
note is.

A **not-installed** hit MUST carry **no install-state copy and no pill**, mirroring the catalog result
surface, which marks the installed row and says nothing at all for a row that is not installed.

The strings “Installed.” and “Not installed.” are **WITHDRAWN** as this surface's copy: neither MUST be
produced, in whole, by the projection or by the surface. The pill's presence carries the first fact and
its absence carries the second, and a row that repeats in a sentence what a chip beside it already says
is the duplicate presentation II8 forbids. The withheld sentence is unaffected — it begins with the same
five characters but is one indivisible pinned string, and it stays. Nothing here changes TM5 either,
whose own tap-detail rows keep both withdrawn strings on the surface TM5 governs.

A hit MUST be selectable **exactly when its identity is unambiguous**, in **either** install state. A
hit's identity is ambiguous when its bare token is also carried by the catalog for the same kind, or
when another hit this source emits carries the same `PackageID`. An ambiguous hit MUST NOT be
selectable, because the existing resolution order resolves the catalog first and would present a
**different package** than the row the user chose. The projection MUST report that routability as a
fact of the hit — a value a test can read directly — so the presenting surface does not re-derive it,
and it MUST NOT be derived from the install state, which cannot express non-collision or uniqueness.
An ambiguous hit MUST still be **presented and installable**: only its detail route is withheld, and
its mutation target stays the bare `PackageID`.

An **installed**, unambiguous hit MUST open the receipt-backed detail `installed-inventory` owns,
selected by its exact `PackageID` through the existing resolution order.

A **not-installed**, unambiguous hit MUST open a **minimal detail composed exclusively from the
resident tap inventory**. That rendering MUST perform **no tap-source read** (TM5), MUST consult **no
catalog record** and MUST create none (PD6), MUST add nothing to the catalog snapshot, to catalog
search or to the index, and MUST cost **no brew invocation** — it is composed from names the tap has
**already published** and from this machine's own installed inventory answering that it has none.

That detail MUST present exactly: the package's **identity** — the bare token it is known by, drawn in
the same identity header every other package detail draws; its **kind**; its **tap of origin**; its
**install state**, carried by `tap-management` TM5's exact shipped string “Not installed.”; the
**shared mutation menu**, handed no installed record and no catalog record, with the bare `PackageID`
as its target; and a **footer** carrying the exact copy “Cellar knows this package by name only until
it is installed.”. Where a hit collides with the catalog the pane MUST carry the same collision note
the row carries, worded identically and supplied by the same projection — though no such pane is
reachable while collision is itself a bar to selection, so that clause binds the composition rather
than any reachable state.

It MUST present **nothing else**. In particular it MUST NOT present a description, a version of any
kind, a homepage, a licence, a dependency list, an install count, a deprecation or disabled flag, an
analytics figure or a size on disk: the tap inventory publishes none of them, and obtaining any of them
would require the tap-source read TM5 forbids unconditionally. An installed tap package gets those
facts from its **receipt**, on the pane `installed-inventory` owns; a not-installed one has no receipt,
and the absence is presented as an absence rather than filled with a placeholder, a dash or an empty
row. The pane MUST also present **no trust badge, no trust control and no trust copy** — `package-trust`
PM10 and `tap-management` TM12 bind it exactly as they bind the row — and `package-detail` PD8's
individual-grant marker MUST NOT appear, because a package this machine has not installed has no
origin receipt for that marker to be a fact about.

The strings above MUST be **supplied by the same projection** that answers the composed source, never
composed by the presenting pane, exactly as the row's own sentences are. The footer is this pane's own
pinned copy and MUST be worded in exactly **one place** in the application's sources.

Resolving a selected identity to that rendering MUST use the **resident tap inventory** and MUST resolve
to a rendering **only when exactly one installed third-party tap publishes that `(kind, name)`**. Zero
publishing taps, or several, MUST fall through to the ordinary unavailable-detail state the detail
surface already renders, and MUST NOT guess a tap. That resolution MUST be answered by a pure,
`nonisolated`, `Sendable` projection over the tap inventory, so it is observable with no view rendered
and no process to inject.

This source MUST be presented on its **own surface**, reachable as its own entry in the application's
section list, carrying the exact title “Search our taps” in both that entry and the surface's own
title. It MUST NOT be composed into the catalog query surface: that surface stays **catalog-only**, and
this requirement MUST NOT add a row, a section, a control or a store to it.

The two surfaces answer **separate keystroke turns**, so PS6's ceiling is not shared and MUST NOT be
restated as a combined budget. Instead: composing this source for **one keystroke** over a resident tap
inventory of realistic size MUST hold p95 below the **same 8 millisecond ceiling** PS6 sets for the
catalog, and PS6's own measurement over the catalog index MUST be **unchanged** — same fixture, same
method, same ceiling, unaffected by this source's existence.

#### Scenario: A tap package the catalog does not carry is found by a non-empty query

- GIVEN installed tap `acme/tools` publishing formulae `acme/tools/widget`, `acme/tools/widget-cli`
  and `acme/tools/superwidget`, and a catalog carrying none of them
- WHEN the query `widget` is composed against that tap inventory
- THEN all three are returned in the order `widget`, `widget-cli`, `superwidget`, by exact, then
  prefix, then substring class
- AND each reports tap of origin `acme/tools` and its published qualified name
- Verification: `unit`

#### Scenario: The ladder is token-aware over the shared normalisation

- GIVEN an installed tap publishing formula `acme/tools/gentle-ai`, whose bare token normalises to the
  two tokens `gentle ai`
- WHEN the queries `ai`, `gent` and `tle` are composed in turn
- THEN `ai` ranks it **exact**, as a whole normalised token rather than as a substring
- AND `gent` ranks it **prefix**, as a token prefix, and `tle` ranks it **substring**
- Verification: `unit`

#### Scenario: The composed order is total and reproducible

- GIVEN installed taps `acme/tools` and `bravo/tools`, each publishing a formula and a cask whose bare
  token is `widget`, all four in the same match class
- WHEN the same query is composed twice
- THEN the order is `acme/tools` formula, `bravo/tools` formula, `acme/tools` cask, `bravo/tools` cask
  in both runs, by bare token, then kind, then tap name
- Verification: `unit`

#### Scenario: A hit carries its six facts and its copy, and nothing else

- GIVEN an installed tap publishing cask token `acme/tools/widget`, with no catalog record and no
  installed record for it
- WHEN every fact the hit exposes is enumerated
- THEN they are exactly kind `cask`, bare token `widget`, published name `acme/tools/widget`, tap of
  origin `acme/tools`, an install state, and an offered version — absent here, because this hit is not
  installed — with the projection-supplied note for that install state, absent here because only the
  withheld state pins one, and a collision note present only when the hit collides
- AND no description, published version, homepage, license, dependency list, install count, deprecation
  flag, disabled flag or size exists in any member, and no exposed value is a placeholder standing for
  absence
- AND the one further member is the **mutation handoff** added in round 5 — this machine's own installed
  receipt for the hit — absent here because this hit is not installed, so the enumeration still exposes
  six facts and carries no tap-published value
- Verification: `unit`

#### Scenario: The kind filter restricts the composed source

- GIVEN an installed tap publishing formula `acme/tools/widget` and cask token `acme/tools/widget`
- WHEN the query `widget` is composed restricted to `cask`
- THEN exactly one hit is returned and its kind is `cask`
- AND the declared filter set is unchanged, with no member added for this source
- Verification: `unit`

#### Scenario: An empty query lists everything the installed taps publish

- GIVEN installed taps `acme/tools` and `bravo/tools` publishing forty packages between them
- WHEN the query is the empty string, and again a whitespace-only string
- THEN all forty are returned in both cases, ordered by bare token, then kind, then tap name
- AND nothing is thrown and no result is withheld
- Verification: `unit`

#### Scenario: An unavailable or empty inventory is an ordinary empty state, never an error

- GIVEN a tap inventory unavailable because brew is absent, separately one whose refresh failed, and
  separately an available inventory in which no installed third-party tap publishes anything
- WHEN the surface's state is composed for an empty query in each case
- THEN the first two carry exactly “No packages from your taps.” and the third exactly “Your taps
  publish nothing yet.”
- AND no error, failure copy or retry demand is produced in any case, and the catalog results for the
  same query are unchanged
- Verification: `unit`

#### Scenario: A catalog collision is reported on the hit and never suppressed

- GIVEN the catalog carries formula `wget` and installed tap `acme/tools` publishes
  `acme/tools/wget`
- WHEN the query `wget` is composed
- THEN the tap hit is present, reports the collision as a fact, and carries exactly the copy
  “Also in the catalog. Homebrew installs the catalog package.”
- AND its row identity differs from the catalog row's identity, while its mutation target remains the
  bare `PackageID` for `(formula, wget)`, with no qualified token anywhere in the argv it produces
- Verification: `unit`

#### Scenario: The three install states stay distinct, and only the withheld state pins a sentence

- GIVEN three tap packages under installed taps: one whose installed record reports the same tap, one
  whose installed record withholds its tap under an `untrusted` tap that publishes it, and one with no
  installed record
- WHEN each hit's install state, its installed-ness and its projection-supplied note are read
- THEN the three states remain distinct values, never collapsed into two, and the first two report
  themselves installed while the third does not — each as a fact, not as a sentence
- AND only the withheld hit carries a note, exactly “Installed. Homebrew withholds its tap while this
  tap is untrusted.”, while the other two carry none
- AND neither “Installed.” nor “Not installed.” is produced for any of the three
- Verification: `unit`

#### Scenario: Only an installed hit its receipt reports outdated exposes an offered version

- GIVEN four tap packages under installed taps: one whose installed record reports the same tap and is
  outdated toward a newer version, one whose installed record reports the same tap and is up to date,
  one with no installed record at all, and one whose installed record withholds its tap under an
  `untrusted` tap that publishes it and is outdated toward a different newer version
- WHEN each hit's offered version is read
- THEN the first reports exactly the version its own receipt offers, and the fourth reports exactly the
  version its own receipt offers, so the withheld state — which is installed — is not silently excluded
- AND the second and the third report none at all, as an absence rather than an empty string, so an
  up-to-date installed hit and a not-installed hit are indistinguishable on this fact
- AND no hit's offered version equals the version that hit has installed, so the fact is the version
  being offered and never a restatement of the one already present
- AND each hit's **mutation handoff** — the installed record it hands the shared mutation spine — is
  present for the first, the second and the fourth, each being that hit's own receipt, and absent for
  the third, resolved by the same tap-aware handoff rather than by a bare identity lookup
- AND a hit whose bare token the catalog also carries, whose only resident receipt belongs to the
  catalog's own tap rather than to the publishing tap, carries **no** record at all, so the catalog
  package's receipt is never attached to a tap row
- Verification: `unit`

#### Scenario: A hit with an ambiguous identity is not routable, whatever its install state

- GIVEN an installed tap hit whose bare token the catalog also carries for the same kind, a
  not-installed hit whose bare token the catalog also carries, and two hits published by different taps
  that carry the same `PackageID`
- WHEN each hit's routability to a detail is read
- THEN each of them reports itself as non-routable, so the catalog-first resolution can never present a
  different package than the row chosen
- AND each is still presented and still offers its install, with the bare `PackageID` as the mutation
  target
- AND an unambiguous hit of each install state reports its exact `PackageID` as routable, so the rule
  is identity's alone and never the install state's
- Verification: `unit`

#### Scenario: Hide-installed composes above the tap source, and no outdated control exists

- GIVEN a non-empty query matching one installed and one not-installed tap package
- WHEN a hide-installed subtraction is applied
- THEN only the not-installed hit is returned
- AND the controls this surface offers are enumerated and contain no outdated predicate, so no enabled
  control is inert
- Verification: `unit`

#### Scenario: The tap surface holds the same ceiling on its own turn

- GIVEN a resident tap inventory of realistic size — several taps publishing approximately 500
  packages in total
- WHEN at least 100 representative as-you-type queries of varying length each compose this source once,
  on their own keystroke turn
- THEN the 95th-percentile duration of composing it is below 8 milliseconds
- AND PS6's own catalog measurement runs over its own fixture, unchanged in fixture, method and
  ceiling, with no tap inventory in its turn
- Verification: `unit`

#### Scenario: The tap surface is its own titled entry, and its ambiguous rows are inert

- GIVEN the source of the surface that presents this source and the application's section list
- WHEN the surface's title, its section-list entry, and the rule that gates a row's selection are
  inspected
- THEN the section-list entry and the surface title are both exactly “Search our taps”
- AND the surface is its own entry rather than a section of the catalog query surface, and a row is
  selectable on the projection's routability alone — so an ambiguous hit is inert and an unambiguous
  not-installed hit is not
- Verification: `unit-app`

#### Scenario: An installed tap hit opens the receipt-backed detail

- GIVEN an installed tap package chosen from the composed source, with no catalog record for its
  `(kind, name)` and no other emitted hit carrying the same `PackageID`, so its identity is unambiguous
- WHEN that choice is resolved by its exact `PackageID`
- THEN the receipt-backed detail `installed-inventory` owns is presented, through the existing
  resolution order and with no routing branch added for this source
- Verification: `unit-app`

#### Scenario: A not-installed tap package resolves to exactly one publishing tap and its four names

- GIVEN a resident tap inventory in which `acme/tools` publishes formula `acme/tools/widget` the
  catalog does not carry, this Mac has no receipt for it, and separately a `(kind, name)` no installed
  third-party tap publishes and a `(kind, name)` two third-party taps both publish
- WHEN each identity is resolved against that inventory for a name-only detail
- THEN `widget` resolves to exactly one rendering, whose facts are its bare token, its kind, its tap of
  origin `acme/tools` and the exact install-state string “Not installed.”, with the footer copy
  “Cellar knows this package by name only until it is installed.” and no other value of any kind — no
  description, no version, no homepage, no licence, no dependency list, no install count, no
  deprecation or disabled flag and no size
- AND the unpublished identity and the doubly-published one both resolve to nothing, so no tap is
  guessed
- AND a package installed from a tap whose tap Homebrew withholds still resolves through the
  receipt-backed route rather than through this one, because it has a receipt
- Verification: `unit`

#### Scenario: The name-only tap detail composes no catalog field and no trust presentation

- GIVEN the sources of the detail surface and of the pane that renders a not-installed tap package
- WHEN the pane is scanned for a description, a version, a homepage, a licence, a dependency list, an
  analytics figure or a size field, for any trust type name, badge, control or grant marker, and for
  where the resolution branch sits and where the pane's footer copy is worded
- THEN the pane composes none of those fields and no trust presentation of any kind
- AND the detail surface resolves this rendering in a **third** branch, after the catalog branch and
  after the receipt branch, so an installed package still reaches its receipt-backed pane first
- AND the resident tap inventory is passed to the detail surface at its single construction site, and
  the footer copy appears in exactly one place in the application's sources
- Verification: `unit-app`

#### Scenario: The tap search surface composes no trust gate and no local copy

- GIVEN the source of the projection that answers the composed source and the source of the surface
  that presents it
- WHEN both are scanned for a tap-trust or per-package-trust type name, for a trust badge or a trust
  control, for the withheld-state and collision copies, for the two withdrawn strings, and for the
  component that draws the installed mark
- THEN neither contains a trust type name, a trust badge or a trust control, and the mutation
  affordances are offered for every hit whatever the origin tap's trust state
- AND the withheld-state note and the collision note are produced by the projection, with no such copy
  composed by the presenting surface itself, and neither file produces “Installed.” or “Not installed.”
- AND the installed mark is the **one shared status-pill component the catalog result surface draws**,
  referenced by both surfaces, with its label composed by neither of them and by no projection
- Verification: `unit-app`

#### Scenario: Both search surfaces mark an available update with the one shared update pill

- GIVEN the source of the surface that presents this source and the source of the catalog result row
- WHEN both are scanned for the component that draws the update mark, for where each draws it relative
  to the installed mark, and for any update wording of their own
- THEN both reference the **same** update-pill component, handing it the offered version as a value,
  and that component is declared exactly once
- AND the presenting surface draws it **after** the installed mark, as the catalog result row does, and
  gates it on the offered version's presence alone rather than on any install state it re-derives
- AND neither surface composes update wording of its own: the pill's label appears only where the
  component is declared
- Verification: `unit-app`

#### Scenario: An installed tap row reaches the shared mutation menu with its installed record

- GIVEN the source of the surface that presents this source and the source of the shared mutation menu
- WHEN the entry the surface hands that menu is inspected, together with the branch the menu takes on
  it and every verb, argv, mutation target and command type the surface declares for itself
- THEN the surface hands the menu the hit's **installed record**, so an installed hit takes the menu's
  installed branch and a not-installed hit takes its install branch, with the bare mutation target
  unchanged in both cases
- AND the record it hands is the one the projection resolved, never one the surface looks up, derives
  or re-keys, and it hands **no catalog record** at all
- AND the surface declares no mutation command, no mutation target, no submission and no
  formula-or-cask narrowing of its own, so Reinstall, Uninstall…, Uninstall and Zap…, Upgrade and
  Pin/Unpin are the shared menu's and are worded only where that menu declares them
- Verification: `unit-app`

#### Scenario: Composing the tap source reaches no process layer

- GIVEN the source of the projection that answers the composed source and the source of the surface
  that presents it
- WHEN both are scanned for any reference to the brew-process execution layer, to `Process`, or to a
  store refresh triggered by presenting the surface
- THEN neither contains one
- AND the composition takes only already-resident values as its input, with no process-launcher
  dependency to inject
- Verification: `unit-app`

#### Scenario: The catalog query surface is untouched by this source

- GIVEN the source of the catalog query surface, as it stands before this change and after it
- WHEN it is compared against its base revision and scanned for any reference to this source's
  projection or to its surface
- THEN the two revisions are identical, with a zero-line difference
- AND it contains no reference to the projection or to the surface, so nothing from this source is
  composed into catalog search
- Verification: `unit-app`

## Notes for archive

- The ADDED block is appended after the capability's current last requirement and promoted as **PS8**.
  PS1–PS7 are byte-identical. `openspec/specs/package-search/spec.md` carries **no `<!-- PS# -->`
  markers** — only `tap-management` uses marker comments — so PS8 is an ordinal label used in prose,
  not a token in the file.
- **The verification-class table above is NOT promoted.** `openspec/specs/package-search/spec.md`
  carries no `## Verification classes` table today (only `app-updates` and `release-distribution` do),
  and this delta adds none: the table is delta-local provenance and only the per-scenario inline
  `- Verification:` lines promote with the requirement. The class names are the established `unit` and
  `unit-app`; no new class is introduced.
- **`package-mutation` is activated, not changed — no delta.** PM10 already mandates the bare-token
  argv this source installs with, already forbids the pre-launch trust gate on both granularities,
  already supplies the typed refusal copy and the Trust recovery, and already enforces the absence
  structurally by a source-scanning assertion over the mutation command surface. This requirement
  cites PM10 rather than restating it; the argv enumeration in PM10's "No mutation argv anywhere
  carries a qualified package token" scenario gains no new family, because the install this source
  offers is the existing family with the existing bare token.
- **`installed-inventory` is activated, not changed — no delta.** II7 keeps its package-graph
  direction (`BrewClient` may import `Catalog`, never the reverse), II8 supplies the
  composed-above-the-index discipline this requirement extends, and II15 supplies the receipt-backed
  detail an installed tap hit lands on.
- PS6's own scenario keeps its M1 text byte-for-byte. The measurement here is a **separate** one over
  this source's own keystroke turn against the same 8 ms ceiling — not a combined budget, and not a
  relaxation. The two surfaces no longer share a turn, which is why the earlier combined-turn wording
  was withdrawn in revision 3.
- **The untouched-catalog-surface scenario is concrete in the app target.** `rules.specs` keeps view
  names out of scenario text, so it names "the catalog query surface"; the assertion is over
  `cellar/Browse/BrowseView.swift` — a zero-line diff against the base revision, and no reference to
  the tap search projection or its view. This is the structural guarantee that Browse stays
  catalog-only.
- **The string “From your taps” is withdrawn** by the 2026-08-25 scope change and appears nowhere in
  this delta: it named a Browse section that no longer exists. The surface title “Search our taps” and
  the two empty-state strings replace it, all three **new copy** with no shipped precedent.
- **The strings “Installed.” and “Not installed.” are withdrawn** by the round-3 maintainer feedback and
  are **not promoted**. This delta never pinned them into `openspec/specs/**` — the whole PS8 block is
  ADDED and lands for the first time at archive — so the withdrawal costs no MODIFIED block and no
  destructive-delta warning. TM5 keeps both strings, unchanged, for the tap-detail rows it governs
  (`openspec/specs/tap-management/spec.md`, `TapPackage.statusExplanation`); nothing about that surface
  moves. What replaces them here is a **presentation** obligation, not copy: the installed state is
  marked by the one shared status pill the catalog result surface already draws, whose label lives in
  that component. The pinned-copy table in `specs/README.md` records the withdrawal.
- **The offered version pins no copy and promotes none.** Round 4 adds a **fact**, not a sentence: the
  version brew currently offers for a package this machine has installed. Its whole presentation is the
  shared update pill's, whose label lives in that component exactly as the installed pill's does, so this
  delta's pinned-copy table gains no row. `installed-inventory` is again **activated, not changed** — II4
  already defines the outdated rule this fact is gated on, including the self-updating-cask exclusion, and
  II5 already keeps `hasNewerVersion` out of that rule; this requirement reads both through the shipped
  receipt rather than restating either.
- **`package-detail` PD6 is unaffected by round 4.** The offered version comes from the **installed
  receipt**, not from a catalog record and not from a tap-source read, so the catalog-membership answer
  PD6 scopes stays exactly what it was: a collision `Bool`, never a contributor to a hit's content. m10's
  DD-5 — which keeps a "latest version" fact row off the receipt **detail** pane, because `catalogVersion`
  falls back to the installed version when brew reports nothing — is likewise untouched: this fact is
  gated on the receipt's own `isOutdated`, so the fallback case is never the case that renders.
- **Round 5 pins no copy and re-implements no verb.** The verbs the installed branch offers — Reinstall,
  Uninstall…, Uninstall and Zap…, Upgrade and Pin/Unpin — are the shipped shared menu's, worded where that
  component declares them, so this delta's pinned-copy table gains no row and its no-local-copy scan gains
  no string. `package-mutation` is **activated, not changed** for the third time: PM10's argv enumeration
  gains no family, because every one of those verbs is an existing family over the existing bare token, and
  the affordances stay unconditional with no trust gate on either granularity. `installed-inventory` is
  likewise **activated, not changed**: II4's outdated rule still gates the Upgrade verb through the
  receipt, exactly as it gates the offered version.
- **The round-5 member is a handoff, not a seventh fact.** The hit gains this machine's own installed
  receipt so the shared mutation spine can be handed the record it already takes; it publishes nothing the
  tap declares, so the six-fact ceiling and the tap-source prohibition TM5 states are both untouched. The
  facts scenario enumerates it by name rather than letting an unlisted member sit in the enumeration it
  reads. `package-detail` **PD6 is unaffected**: the record is the *installed* receipt, resolved by the
  tap-aware handoff, so a colliding hit still hands over its own tap row's receipt and never the catalog
  package's — the membership answer stays a collision `Bool` and contributes nothing to a hit's content.
- **Round 6 reverses a 2026-08-24 decision and pins one new string.** The decision block above records
  “a not-installed hit is non-selectable”; the round-6 block records the maintainer's reversal and the
  reason. Only the **route** changes: ambiguity still withholds it, the mutation target is still the
  bare `PackageID`, and no row presentation moves. The one new pinned string is the pane's footer,
  “Cellar knows this package by name only until it is installed.”, which has no shipped precedent and
  is added to the pinned-copy table in `specs/README.md`.
- **Round 6 activates `package-detail` and `tap-management` rather than weakening either.** PD6 gains a
  clause covering an inventory-fed *rendering* on the same four negations its receipt-backed clause
  already carries, and TM5's tap-source prohibition is **reaffirmed** — the pane is composed from names
  the tap already published, which is precisely why it is representable. Both are MODIFIED blocks in
  this change with one added scenario each; neither loses a sentence.
- **PD8 does not reach this pane.** The individual-grant marker is a fact about a receipt's tap of
  origin, and a package this machine has not installed has no receipt. The pane asserts the marker's
  **absence** rather than rendering it, so PD8 needs no delta for the third round running.
