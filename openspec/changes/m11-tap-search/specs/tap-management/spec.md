# Delta for tap-management

Existing capability — `openspec/specs/tap-management/spec.md` (**13 requirements / 58 scenarios**,
established by `2026-08-05-m3-taps` and amended by `2026-08-23-m7-tap-trust`,
`2026-08-24-m9-per-package-trust` and `2026-08-24-m10-third-party-detail`). This delta is **2 MODIFIED,
0 added, 0 removed, 0 renamed**: each modified block keeps **every** scenario it carries today
byte-identical and adds one or two, taking the capability to **13 requirements / 61 scenarios**.

| Block | Heading | Existing scenarios (byte-identical) | Added |
|---|---|---|---|
| `<!-- TM5 -->` | Tap package inventory preserves identity without entering the catalog | 10 | 2 |
| `<!-- TM11 -->` | Tap management does not expand into adjacent product capabilities | 2 | 1 |

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. Both MODIFIED blocks are whole-block replacements copied from the main spec and then edited;
each is a strict superset of the text it replaces, and in both the edit is **one added paragraph plus
its `(Previously: …)` line**. No existing sentence is deleted or reworded, and no prohibition is
weakened: the catalog-ingestion ban and the tap-source-read ban are reproduced verbatim and restated
as unconditional.

**Marker/numbering drift, recorded once.** `explore.md` and `proposal.md` call the adjacent-capabilities
requirement **TM10** and the trust-presentation requirement **TM11**. In the main spec those blocks
carry the markers **`<!-- TM11 -->`** (`:532-550`) and **`<!-- TM12 -->`** (`:560`) respectively — the
explore numbering is off by one from `2026-08-23-m7-tap-trust` onward. This delta uses the **main
spec's markers**, which are the tokens in the file. The requirement the decisions record as "TM11
untouched — no Untrusted badge in Browse" is the main spec's **TM12**, and it is indeed untouched: no
delta here, and `package-search` PS8 forbids the badge and the control outright, so TM12's
one-projection trust presentation gains no third consumer.

**Both blocks land in the first work unit (proposal risk R2).** Read narrowly, TM5's catalog clause and
TM11's exclusion list both bind this capability's own surface, and m11 adds no action to Taps. Read
broadly, they ban the change outright. m10 established the house answer to exactly that ambiguity —
state the clause's meaning rather than argue it — and this delta applies it to the search half.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m11-tap-search/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour | `swift test --package-path Packages/CellarCore` | **3** |

## MODIFIED Requirements

### Requirement: Tap package inventory preserves identity without entering the catalog

Every tap package MUST retain formula-or-cask kind as part of its identity. For a selected tap, a
formula display name and a cask display name MAY remove only the exact `<selected-tap>/` prefix; no
other prefix or substring MAY be removed. `brew tap-info --json` publishes cask tokens fully qualified
exactly as it publishes formula names, so the same rule applies to both kinds, and the projected
identity MUST be the bare token brew installs by; the published, fully qualified name MUST be retained
alongside it. Formula and cask entries with the same token MUST remain distinct.

Installed status MUST resolve into exactly **three typed states**, which MUST remain distinct values
and MUST NOT be collapsed into two:

1. **Installed** — a complete installed snapshot reports a package of the same kind whose exact
   `InstalledPackage.tap` equals the selected tap. It MUST offer **Show in Installed**.
2. **Installed, tap withheld** — the installed snapshot reports a package of the same kind and name
   whose `tap` is **absent** (Homebrew withholds the tap of a package it will not load), **and** the
   selected tap's trust state is `untrusted`, **and** the selected tap publishes this exact
   `(kind, name)`. It MUST show the exact copy “Installed. Homebrew withholds its tap while this tap is
   untrusted.” and it MUST still offer **Show in Installed**, because the handoff selects by exact
   `PackageID` and that identity is exact regardless of what brew withholds.
3. **Not installed** — every other case, including an absent `tap` under a tap whose trust state is
   `trusted` or `unreported`, and an absent `tap` for a `(kind, name)` the selected tap does not
   publish. It MUST show the exact copy “Not installed.” — a statement about this Mac, not about the
   catalog, because a third-party package is never in the catalog whether installed or not.

An absent tap MUST NOT be treated as equal to the selected tap, and MUST NOT be treated as equal to the
empty string; `installed-inventory` owns preserving that absence. The middle state's copy MUST be
scoped to the **tap** and MUST NOT state or imply that the package is untrusted, because a per-package
grant can make a package loadable while its tap is not trusted. Tap packages MUST NOT enter the catalog
snapshot, catalog search, or catalog detail; PD6 remains unchanged. Selecting a tap package MUST NOT
create a **catalog** record for it and MUST NOT perform a tap-source read to complete a package
detail — that is the whole of this prohibition. It does not reach a detail composed **exclusively from
the installed receipt**: **Show in Installed** already hands off by exact `PackageID` and lands on the
reduced, receipt-backed detail `installed-inventory` owns, which synthesizes no catalog record, adds
nothing to catalog search, and spawns no additional brew invocation.

Nor does the **catalog search** half of that prohibition reach a search surface composed **above the
index**. Tap packages MUST NOT enter the catalog snapshot, the catalog index or a catalog result —
that clause is unchanged and unweakened — but the inventory this capability acquires MAY feed a surface
**owned by another capability**, provided that surface composes its hits above the index, creates no
catalog record, adds nothing to the snapshot or to the index, and spawns no additional brew invocation.
`package-search` owns finding a tap package from the query surface and states its own rules for it;
`package-mutation` owns installing one on the shared mutation spine with the bare token PM10 mandates.
Every such consumer MUST still perform **no tap-source read**: that prohibition is unconditional and
binds this capability's own surfaces and every outside consumer alike, which is why a surface fed from
this inventory can present a name, a kind, a tap of origin and an install state — and nothing more.

That last clause is **reaffirmed, not relaxed, for a detail surface**: a consumer MAY compose a
package **detail** from this inventory on exactly the terms above and no others, because the four
things it presents are things the tap has **already published** rather than things a source read would
have to fetch — which is precisely why such a detail carries no description, no version, no homepage,
no licence, no dependency list, no install count, no deprecation or disabled flag and no size. A
consumer that needs any of those for a package this machine does not have MUST do without it: the
tap-source read remains forbidden here as everywhere, and the absence MUST be presented as an absence
rather than filled from any other source.

The inventory MUST be filterable by package name and kind. A large inventory MUST remain usable by
presenting only the filtered/visible rows needed at a time rather than requiring every row to be
presented eagerly.
(Previously: installed status came only from an exact `InstalledPackage.tap` equality, so a package
installed from an untrusted tap — whose tap brew withholds — was *mandated* to read “Not installed.”,
a false statement about this Mac.)
(Previously: the catalog paragraph ended “…and selection MUST NOT create a third-party detail
fallback.”, a bare phrase broad enough to read as a blanket ban on any detail for a tap package,
including one built solely from the installed receipt.)
(Previously: the catalog paragraph carved out a receipt-backed **detail** only, so its “catalog search”
clause was broad enough to read as a ban on this inventory feeding any search surface at all, including
one composed above the index and owned by another capability.)
(Previously: the outside-consumer paragraph named a **search surface** only, so a *detail* composed from
the same four already-published names had no stated home — leaving the unconditional tap-source
prohibition to be read as a ban on the rendering rather than as the reason it is reduced.)

#### Scenario: Only the selected tap prefix is normalized

- GIVEN selected tap `acme/tools` publishes formulae `acme/tools/widget` and `other/tap/widget`
- WHEN their display names are projected
- THEN they are `widget` and `other/tap/widget`, respectively
- Verification: `unit`

#### Scenario: A fully qualified cask token matches the installed cask

- GIVEN selected tap `acme/tools` publishes cask token `acme/tools/widget`
- AND cask `widget` is installed from tap `acme/tools`
- WHEN the tap inventory is presented
- THEN the cask displays as `widget`, keeps `acme/tools/widget` as its published name, and offers **Show in Installed**
- Verification: `unit`

#### Scenario: Equal formula and cask tokens remain distinct

- GIVEN a formula and cask both displayed as `widget`
- WHEN inventory identities and kind filtering are inspected
- THEN two entries remain, one formula and one cask
- Verification: `unit`

#### Scenario: Exact installed tap controls the handoff

- GIVEN formula `widget` has installed tap `acme/tools`, while same-named cask has `other/tools`
- WHEN `acme/tools` inventory is presented
- THEN only the formula offers **Show in Installed**
- AND the cask shows “Not installed.”
- Verification: `unit`

#### Scenario: A withheld tap under an untrusted tap reads as installed, not as absent

- GIVEN selected tap `acme/tools` has trust state `untrusted` and publishes cask token `acme/tools/widget`
- AND the installed snapshot reports cask `widget` with no tap
- WHEN the tap inventory is presented
- THEN that cask reports the middle state with the exact copy “Installed. Homebrew withholds its tap while this tap is untrusted.”
- AND it still offers **Show in Installed**
- Verification: `unit`

#### Scenario: A withheld tap is not claimed by a tap that does not publish it

- GIVEN selected tap `acme/tools` has trust state `untrusted` and does not publish cask `stranger`
- AND the installed snapshot reports cask `stranger` with no tap
- WHEN the tap inventory is presented
- THEN `stranger` is absent from that tap's inventory and no middle-state claim is made for it
- Verification: `unit`

#### Scenario: A withheld tap under a trusted or unreported tap is still “Not installed.”

- GIVEN selected tap `acme/tools` in turn has trust state `trusted` and `unreported`, and publishes cask token `acme/tools/widget`
- AND the installed snapshot reports cask `widget` with no tap
- WHEN the tap inventory is presented
- THEN both cases show the exact copy “Not installed.”
- AND neither presents the withheld-tap copy
- Verification: `unit`

#### Scenario: Tap names never become catalog records

- GIVEN an uninstalled package published only by a third-party tap
- WHEN catalog snapshot, search, and detail lookup are queried
- THEN it is absent from snapshot and search and detail returns ordinary not-found
- Verification: `unit`

#### Scenario: The handoff lands on a receipt-backed detail, not on a catalog record

- GIVEN selected tap `acme/tools` publishes formula `acme/tools/widget`
- AND the installed snapshot reports formula `widget` with tap `acme/tools`, and the catalog carries no
  record for it
- WHEN **Show in Installed** is taken by exact `PackageID` and the resulting detail is resolved
- THEN that detail is composed from the installed snapshot record alone
- AND the catalog snapshot, catalog search and catalog detail lookup for `widget` are unchanged, with
  the catalog lookup still returning the ordinary not-found result
- AND no additional brew invocation is recorded
- Verification: `unit`

#### Scenario: Large inventory can be narrowed without eager presentation

- GIVEN a tap containing thousands of formulae and casks
- WHEN a name-and-kind filter matches three casks
- THEN exactly those three results are presented as the visible result set
- AND presenting them does not require every non-matching row to be presented first
- Verification: `unit`

#### Scenario: The inventory feeds an outside search surface without entering the catalog

- GIVEN selected tap `acme/tools` publishes formula `acme/tools/widget`, and the catalog carries no
  record for `widget`
- WHEN a search surface composed above the index exclusively from this inventory returns `widget` for
  the query `widget`
- THEN the catalog snapshot, catalog search and catalog detail lookup for `widget` are unchanged, with
  the catalog lookup still returning the ordinary not-found result
- AND no tap-source read is performed and no additional brew invocation is recorded
- Verification: `unit`

#### Scenario: A detail composed from this inventory carries the four published names and nothing else

- GIVEN selected tap `acme/tools` publishes formula `acme/tools/widget`, the catalog carries no record
  for `widget`, and this Mac has no receipt for it
- WHEN an outside consumer composes a package **detail** for `widget` from this inventory
- THEN everything it can present is enumerated, and it is exactly the bare token, the kind, the tap of
  origin and the install state
- AND no description, version, homepage, licence, dependency list, install count, deprecation flag,
  disabled flag or size is representable, because no tap-source read is performed and none may be
- AND no additional brew invocation is recorded
- Verification: `unit`

### Requirement: Tap management does not expand into adjacent product capabilities

The capability MUST NOT offer Brewfile import/export, package installation from tap inventory,
third-party catalog ingestion or search, official-source cloning, tap security scanning, arbitrary Git
management, cleanup, disk usage, or service behavior. It MUST NOT create receipt-driven behavior.

Showing a tap's trust state and offering to grant or revoke it is **not** tap security scanning: the
state is read from brew's own snapshot and the grant is brew's own command. The capability MUST NOT
inspect, analyse, score or judge a tap's contents, and MUST NOT derive a trust recommendation.

The exclusions above bind **this capability's own surface** — the action set tap management itself
exposes, enumerated below. They are not a repository-wide ban on the tap inventory as a data source.
`package-search` owns finding a package published by an installed tap from the query surface it owns,
and `package-mutation` owns installing that package on the shared mutation spine with the bare token
PM10 mandates. Neither action is exposed by this capability's surface, neither adds a member to the
enumerated set below, and neither ingests a tap package into the catalog — TM5 and PD6 continue to
forbid that, and the tap-source read stays forbidden for every consumer. What this requirement
continues to exclude is **tap management itself** growing an install verb, a catalog ingestion, or a
search surface of its own beyond the name-and-kind inventory filter TM5 already grants it.
(Previously: the enumerated action set had six members and predated any trust surface.)
(Previously: the exclusion of package installation from tap inventory and of third-party catalog
ingestion or search named no surface, so it read as a capability-level ban wherever the tap inventory
is the source — including a query surface owned by `package-search` and an install owned by
`package-mutation`.)

#### Scenario: Enumerated tap actions stay within scope

- GIVEN the tap-management capability is available
- WHEN all actions exposed by tap management are enumerated
- THEN they are refresh, filter, Installed handoff, canonical add, plain untap, eligible force untap, trust, and untrust
- AND none performs an excluded adjacent capability
- Verification: `unit`

#### Scenario: Trust is a reported state and a grant, never a verdict

- GIVEN the trust surface
- WHEN everything it presents about a tap is enumerated
- THEN each item is either the state brew reported or a control that submits brew's own grant or revocation
- AND nothing inspects, scores or recommends for or against a tap's contents
- Verification: `unit`

#### Scenario: A tap package found on another surface adds no action here

- GIVEN a query surface owned by `package-search` that finds a package published by an installed tap
  and offers its install on the shared mutation spine
- WHEN all actions exposed by tap management are enumerated again
- THEN the enumerated set is unchanged
- AND tap management exposes no install verb, no catalog ingestion, and no search surface of its own
- Verification: `unit`

## Notes for archive

- **The verification-class table above is NOT promoted.** `openspec/specs/tap-management/spec.md`
  carries no `## Verification classes` table today, and this delta adds none: the table is delta-local
  provenance and only the per-scenario inline `- Verification:` lines promote with their requirements,
  following the precedent `2026-08-23-m7-tap-trust` recorded at
  `openspec/specs/installed-inventory/spec.md:948`. The class names used across this change are the
  established `unit` and `unit-app`; no new class is introduced.
- **Round 6 reaffirms TM5's tap-source prohibition rather than carving another hole in it.** The added
  paragraph grants a *detail* consumer exactly what the search paragraph already granted a *search*
  consumer — the four already-published names — and restates that everything else stays unobtainable.
  The prohibition's text is reproduced verbatim and its scope is unchanged: this capability's own
  surfaces and every outside consumer alike.
- The first MODIFIED block replaces **TM5** in place, under its existing `<!-- TM5 -->` marker; the
  second replaces the requirement under the existing **`<!-- TM11 -->`** marker. TM1–TM4, TM6–TM10,
  TM12 and TM13 are byte-identical, and every scenario both blocks carry today is reproduced
  byte-identical.
- **Numbering drift.** `explore.md` §4.4/§4.5 and `proposal.md` call the adjacent-capabilities
  requirement TM10 and the trust-presentation requirement TM11; the file's markers are `<!-- TM11 -->`
  and `<!-- TM12 -->`. The archive should record the marker numbers, not the explore numbers.
- **TM12 needs no delta.** The tap search surface presents the tap name as a plain fact and no trust
  badge or control at all, so TM12's "exactly one projection supplies the trust presentation" rule
  gains no third consumer. `package-search` PS8 asserts that badge and control absence directly.
- Neither narrowing changes shipped behaviour on the Taps surface: no action is added, no navigation is
  added, and the inventory filter TM5 already grants is untouched.
