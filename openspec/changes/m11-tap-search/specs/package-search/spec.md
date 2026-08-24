# Delta for package-search

Existing capability — `openspec/specs/package-search/spec.md` (**7 requirements / 19 scenarios**,
established by `2026-08-01-m1-catalog-browse` and extended by `2026-08-02-m2-catalog-hardening`). This
delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**: **16 scenarios** are added, taking the
capability to **8 requirements / 35 scenarios**.

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
`sdd/m11-tap-search/state` obs `#7795`): Approach A; the section renders **below** the catalog rows;
the collision note is a neutral statement of Homebrew's resolution with no nudge; the row shows the
tap name only and no trust badge; "Hide installed" subtracts from the tap section; the Outdated chip
hides the section entirely; the search prompt keeps counting catalog records only; a not-installed hit
is non-selectable and an installed hit routes to the m10 receipt pane.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` ("observable behavior of CellarCore types without referencing SwiftUI views") | `swift test --package-path Packages/CellarCore` | **12** |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom that reads the repository source off disk — the established class for app-target composition and source-scan assertions (`openspec/specs/app-updates/spec.md:17`) | `xcodebuild test … -only-testing:cellarTests` | **4** |

## ADDED Requirements

### Requirement: Packages published by installed third-party taps are searchable as a composed source

A package published by an installed third-party tap MUST be findable from the same query surface that
searches the catalog, presented as a **distinct source** rather than as a catalog result. That source
MUST be **composed above the search index and never pushed into it**, on exactly the discipline
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

A hit MUST carry exactly five facts: the package **kind**, the **bare token** brew installs by, the
**published qualified name** the tap declares, the **tap of origin**, and its **install state** —
together with the **projection-supplied copy** for that install state, and the collision note where the
hit collides. It MUST carry nothing else — in particular no description, no version, no homepage, no
license, no dependency list, no install count, no deprecation flag, no disabled flag and no size —
because the tap inventory publishes none of them and obtaining any of them would require the
tap-source read TM5 forbids. An absent fact MUST be absent rather than an empty string, a dash,
`unknown` or any other placeholder.

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

The composed source MUST be produced **only for a non-empty query**. Where PS5 makes an empty catalog
query return the whole filtered catalog, an empty or whitespace-only query MUST here yield **no tap
source at all** rather than the whole tap inventory, and MUST NOT throw. Where the tap inventory is
unavailable — brew absent, or its refresh failed — the source MUST simply be **absent**: never an
error, never a banner on the query surface, and never a reason a catalog result changes.

The query's declared **kind** filter MUST restrict the composed source exactly as it restricts catalog
results, and the declared filter set MUST NOT gain a member (PS4). Installed-state controls MUST be
composed above this source on II8's terms: a hide-installed subtraction MUST remove its installed hits
exactly as it removes installed catalog rows, and while an outdated-only mode is active the composed
source MUST be **absent in whole**, because a tap hit carries no version and can therefore never
satisfy an outdated predicate. The record count presented as the query field's prompt MUST continue to
count **catalog records only**, because that is what the index answers for.

A tap hit's **row identity** MUST be distinct from any catalog row's identity, formed from the tap of
origin, the kind and the bare token, so two rows for the same `(kind, name)` remain separately
addressable. `PackageID` MUST remain the **mutation target** and MUST NOT be reused as the row
identity. Where a hit's bare token is also carried by the catalog for the same kind, the hit MUST be
**presented, never suppressed**, and MUST report the collision as a fact of the hit. That fact MUST be
presented with the exact copy “Also in the catalog. Homebrew installs the catalog package.” — a
neutral statement of Homebrew's own resolution, carrying no recommendation, no warning styling and no
suggestion to disambiguate. It MUST be supplied by the same projection that answers the source, so the
presenting surface composes none of that copy locally.

Install MUST be offered on the **shared mutation spine, unconditionally**, with the existing
bare-token argv. No new command family and no new argv shape MUST be introduced, and the mutation
target MUST remain the bare `PackageID` even for a colliding hit: qualifying the token to disambiguate
is forbidden by `package-mutation` PM10, whose prohibition binds every path on that spine. This
surface MUST NOT block, disable, hide, delay or pre-qualify the install — or any other affordance —
on a tap's trust state or on per-package grant state, and MUST NOT read a trust report, store or
projection to decide anything before launch (PM10). It MUST present no trust badge and no trust
control, so `tap-management`'s one-projection trust presentation gains no consumer. An untrusted tap
MUST surface through the already-shipped typed refusal and its Trust recovery, never through a
pre-launch block.

The install state MUST resolve into the **same three distinct states** TM5 defines and MUST NOT be
collapsed into two. Its copy MUST be **supplied by the projection**, never composed by the presenting
surface, and MUST be exactly “Installed.” for the installed state, “Installed. Homebrew withholds its
tap while this tap is untrusted.” for the withheld state — TM5's exact string, scoped to the tap and
never implying the package is untrusted — and “Not installed.”.

An **installed** hit MUST open the receipt-backed detail `installed-inventory` owns, selected by its
exact `PackageID` through the existing resolution order and with no new routing branch — **unless its
identity is ambiguous**. An installed hit's identity is ambiguous when its bare token is also carried
by the catalog for the same kind, or when another hit this source emits carries the same `PackageID`.
In either case the hit MUST NOT be selectable, because the existing resolution order resolves the
catalog first and would present a **different package** than the row the user chose. The projection
MUST report that non-routability as a fact of the hit, so the presenting surface does not re-derive it.
An ambiguous hit MUST still be **presented and installable**: only its detail route is withheld, and
its mutation target stays the bare `PackageID`.

A **not-installed** hit MUST NOT be selectable either: the catalog carries no record for it, no receipt
exists, and the tap-source read that would supply a description or a version is forbidden, so there is
nothing honest to present in a detail pane.

The composed source MUST be presented as a titled section carrying the exact title “From your taps”,
positioned **after** the catalog results rather than interleaved with them. Composing it runs on the
same keystroke turn as the catalog query, so PS6's measured ceiling MUST continue to hold with the
section composed: p95 MUST remain below 8 milliseconds. The ceiling is not relaxed and MUST NOT be
regressed by this source.

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

#### Scenario: A hit carries its five facts and its copy, and nothing else

- GIVEN an installed tap publishing cask token `acme/tools/widget`, with no catalog record and no
  installed record for it
- WHEN every fact the hit exposes is enumerated
- THEN they are exactly kind `cask`, bare token `widget`, published name `acme/tools/widget`, tap of
  origin `acme/tools`, an install state, and the projection-supplied copy for that state — with a
  collision note present only when the hit collides
- AND no description, version, homepage, license, dependency list, install count, deprecation flag,
  disabled flag or size exists in any member, and no exposed value is a placeholder standing for
  absence
- Verification: `unit`

#### Scenario: The kind filter restricts the composed source

- GIVEN an installed tap publishing formula `acme/tools/widget` and cask token `acme/tools/widget`
- WHEN the query `widget` is composed restricted to `cask`
- THEN exactly one hit is returned and its kind is `cask`
- AND the declared filter set is unchanged, with no member added for this source
- Verification: `unit`

#### Scenario: An empty query composes no tap source

- GIVEN an installed tap publishing forty packages
- WHEN the query is the empty string, and again a whitespace-only string
- THEN no tap hit is produced in either case and nothing is thrown
- Verification: `unit`

#### Scenario: An unavailable tap inventory is an absence, not an error

- GIVEN a tap inventory unavailable because brew is absent, and separately one whose refresh failed
- WHEN a non-empty query that would otherwise match a published package is composed in each case
- THEN no tap hit is produced, no error is raised and no error state is reported for the query surface
- AND the catalog results for the same query are unchanged
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

#### Scenario: The three install states stay distinct and carry their exact copy

- GIVEN three tap packages under installed taps: one whose installed record reports the same tap, one
  whose installed record withholds its tap under an `untrusted` tap that publishes it, and one with no
  installed record
- WHEN each hit's install state and its copy are read
- THEN the three states remain distinct values, never collapsed into two
- AND the copy is exactly “Installed.”, “Installed. Homebrew withholds its tap while this tap is
  untrusted.” and “Not installed.” respectively
- Verification: `unit`

#### Scenario: An installed hit with an ambiguous identity is not routable

- GIVEN an installed tap hit whose bare token the catalog also carries for the same kind, and
  separately two installed hits published by different taps that carry the same `PackageID`
- WHEN each hit's routability to a detail is read
- THEN each of them reports itself as non-routable, so the catalog-first resolution can never present a
  different package than the row chosen
- AND each is still presented and still offers its install, with the bare `PackageID` as the mutation
  target
- Verification: `unit`

#### Scenario: Installed-state controls compose above the tap source

- GIVEN a non-empty query matching one installed and one not-installed tap package
- WHEN a hide-installed subtraction is applied, and separately an outdated-only mode is active
- THEN the first case returns only the not-installed hit
- AND the second case returns no tap hit at all
- Verification: `unit`

#### Scenario: The keystroke latency ceiling is not regressed

- GIVEN the realistic fixture PS6 measures over, and a resident tap inventory of realistic size —
  several taps publishing approximately 500 packages in total
- WHEN at least 100 representative as-you-type queries of varying length run the catalog query and
  compose the tap source on the same turn
- THEN the 95th-percentile duration of that combined turn is below 8 milliseconds
- Verification: `unit`

#### Scenario: The tap section is titled, positioned last, and inert when not installed

- GIVEN the source of the surface that presents the composed tap source
- WHEN its section title, its position relative to the catalog results, and the selectability of a
  not-installed hit are inspected
- THEN the title is exactly “From your taps”, the section is presented after the catalog results, and
  a not-installed hit is not selectable
- Verification: `unit-app`

#### Scenario: An installed tap hit opens the receipt-backed detail

- GIVEN an installed tap package chosen from the composed source, with no catalog record for its
  `(kind, name)` and no other emitted hit carrying the same `PackageID`, so its identity is unambiguous
- WHEN that choice is resolved by its exact `PackageID`
- THEN the receipt-backed detail `installed-inventory` owns is presented, through the existing
  resolution order and with no routing branch added for this source
- Verification: `unit-app`

#### Scenario: The tap search surface composes no trust gate and no local copy

- GIVEN the source of the projection that answers the composed source and the source of the surface
  that presents it
- WHEN both are scanned for a tap-trust or per-package-trust type name, for a trust badge or a trust
  control, and for the install-state and collision copies
- THEN neither contains a trust type name, a trust badge or a trust control, and the install
  affordance is offered for every hit whatever the origin tap's trust state
- AND the install-state and collision copies are produced by the projection, with no such copy
  composed by the presenting surface itself
- Verification: `unit-app`

#### Scenario: Composing the tap source reaches no process layer

- GIVEN the source of the projection that answers the composed source and the source of the surface
  that presents it
- WHEN both are scanned for any reference to the brew-process execution layer, to `Process`, or to a
  store refresh triggered by presenting the section
- THEN neither contains one
- AND the composition takes only already-resident values as its input, with no process-launcher
  dependency to inject
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
- PS6's own scenario keeps its M1 text byte-for-byte; the non-regression scenario here is an
  additional measurement over the combined turn, not a restatement or a relaxation of the ceiling.
