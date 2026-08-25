# Delta for package-detail

Existing capability — `openspec/specs/package-detail/spec.md` (**8 requirements / 31 scenarios**,
established by `2026-08-01-m1-catalog-browse`, amended by `2026-08-06-m5-catalog-inspection`,
`2026-08-24-m9-per-package-trust` and `2026-08-24-m10-third-party-detail`). This delta is **1 MODIFIED,
0 added, 0 removed, 0 renamed**: the modified block keeps all **three** scenarios it carries today
**byte-identical** and adds **3 scenarios**, taking the capability to **8 requirements / 34 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. The MODIFIED block is a whole-block replacement copied from the main spec and then edited; it
is a strict superset of the text it replaces. Every textual change is an **addition to the boundary
paragraph** — the parallel of m10's, drawn for a *search surface* instead of a detail surface; then the
inventory-fed rendering (round 6); then the colliding selection (round 7) — each with its own
`(Previously: …)` line. The clause "MUST NOT appear in search results" is reproduced **verbatim**;
this delta narrows nothing about what the catalog projection itself may return, and round 7 adds no
permission to it: the record a colliding selection returns is one the catalog **already covers**.

**This delta lands in the first work unit (proposal risk R2).** Read literally, PD6's second paragraph
already scopes every clause to "the **catalog projection** this capability owns — the snapshot, catalog
search, and the catalog detail lookup", so a section fed exclusively by the resident tap inventory is
not catalog search and violates nothing. But the bare phrase "MUST NOT appear in search results" is
broad enough to be read as a blanket ban, exactly as the m9 archive read the detail half before m10
narrowed it. Shipping m11 against an unamended PD6 would leave the same documented contradiction m10
was careful to avoid, so the boundary is drawn before any surface code lands.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m11-tap-search/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour | `swift test --package-path Packages/CellarCore` | **3** |

## MODIFIED Requirements

### Requirement: Third-party tap packages are outside catalog scope

The catalog covers the `homebrew/core` and `homebrew/cask` taps only. A package published by any
other tap MUST be absent from the snapshot, MUST NOT appear in search results, and a detail lookup
for it MUST return the ordinary not-found result. Its absence MUST NOT be reported as a sync
failure, a decode failure, or an error state.

Every clause above binds the **catalog projection** this capability owns — the snapshot, catalog
search, and the catalog detail lookup. A rendering fed **exclusively by the installed receipt** is not a
catalog detail lookup: it creates no catalog record, adds nothing to the snapshot or to search, consults
no catalog value, and spawns no additional brew invocation, so it neither satisfies nor violates this
requirement. `installed-inventory` owns that reduced, receipt-backed detail for a package the catalog
does not carry. What this requirement continues to forbid is a **catalog** record or a **catalog**
detail result for a package the catalog does not cover — including one synthesized from an installed
record — and that prohibition is unchanged.

The same boundary binds a **search surface**. A search surface fed **exclusively by the resident tap
inventory** is not catalog search: it is composed above the index rather than pushed into it, it
creates no catalog record, it adds nothing to the snapshot and nothing to the index, and it spawns no
additional brew invocation — so it neither satisfies nor violates this requirement. Such a surface MAY
read the catalog for **membership alone** — to report that a hit's bare token is also carried by the
catalog — and that read produces no catalog result for the tap package, creates no catalog record, and
adds nothing to the snapshot or to the index; it draws no catalog value into the hit beyond the fact of
that collision. Such a surface MAY also let a row whose bare token the catalog **does** carry be
selected, resolving it through the **ordinary** detail lookup by that bare identity: what the lookup
then returns is the catalog's **own** record for its **own** package — the record the catalog carried
before any tap was installed and would return for the same identity with no tap inventory resident at
all. That is this capability's own lookup answering for a package it covers, not a catalog result
manufactured for the tap package: no record is created, synthesized or amended, the snapshot and the
index are unchanged, and the tap package contributes nothing to what comes back. `package-search` owns
that composed surface and states its own rules for it. The same boundary, on the
same terms, binds a **rendering fed exclusively by the resident tap inventory**: a detail composed from
the names an installed third-party tap has **already published** — its bare token, its kind, its tap of
origin — together with this capability's neighbours answering that the machine holds no receipt for it
is not a catalog detail lookup. It creates no catalog record, adds nothing to the snapshot, to catalog
search or to the index, consults no catalog value beyond the membership answer already carved out
above, and spawns no additional brew invocation, so it neither satisfies nor violates this requirement.
It is the name-only counterpart of the receipt-backed rendering: where that one is complete because a
receipt exists, this one is deliberately reduced because none does, and it presents the absence as an
absence rather than filling it from a source it may not read. What this requirement continues to forbid is unchanged and unweakened: no tap package MUST
enter the snapshot or the index, and no **catalog** result — nothing the catalog snapshot, the catalog
index or the catalog detail lookup itself returns — MUST exist for a package the catalog does not cover.
The clause "MUST NOT appear in search results" continues to bind every result the catalog projection
returns, to the byte.
(Previously: the requirement stated only the catalog-scope clauses, and was being cited as a blanket ban
on any third-party detail rendering, including one built solely from the installed receipt.)
(Previously: the boundary paragraph named only a receipt-backed **detail**, so the bare clause "MUST NOT
appear in search results" was broad enough to read as a blanket ban on any search surface that finds a
tap package, including one composed above the index from the resident tap inventory.)
(Previously: the boundary paragraph's detail half was carved out for a rendering fed by the **installed
receipt** alone, so a rendering fed by the resident **tap inventory** — for a package this machine does
not have, and therefore has no receipt for — fell under neither carve-out and read as forbidden, even
though it consults no catalog value and reads no tap source.)
(Previously: the search-surface half permitted a **membership** read but said nothing about a selection
made on that surface, so opening the catalog's own detail for a bare token the catalog carries — the
package Homebrew resolves that token to — read as producing “a catalog result” for a tap row, even
though the record returned is the catalog's own and predates the tap entirely.)

#### Scenario: A third-party tap package is a normal not-found

- GIVEN a successful sync and a package name published only by a third-party tap
- WHEN a detail lookup for it runs
- THEN it returns not-found, the sync status remains successful, and no error is raised

#### Scenario: Every snapshot record belongs to a covered tap

- GIVEN a successfully persisted snapshot
- WHEN each record's tap is inspected
- THEN every record reports `homebrew/core` or `homebrew/cask`

#### Scenario: A receipt-backed detail creates no catalog record

- GIVEN an installed package published only by a third-party tap, for which a reduced detail is
  composed from the installed receipt
- WHEN the catalog snapshot, catalog search and catalog detail lookup are queried for it
- THEN it remains absent from the snapshot and from search results, and the detail lookup still returns
  the ordinary not-found result
- AND no catalog record exists for it, synthesized or otherwise
- Verification: `unit`

#### Scenario: A composed tap surface leaves catalog search unchanged

- GIVEN an installed third-party tap publishing a package the catalog does not carry, and a separate
  search surface composed exclusively from that tap inventory for the same query
- WHEN the catalog snapshot, the catalog index's search for that query, and the catalog detail lookup
  for that package are queried with the tap inventory resident
- THEN the search results are identical to those returned with no tap inventory present, and the detail
  lookup still returns the ordinary not-found result
- AND the package remains absent from the snapshot and from the index, with no catalog record for it,
  synthesized or otherwise
- Verification: `unit`

#### Scenario: A name-only tap detail creates no catalog record either

- GIVEN an installed third-party tap publishing a package the catalog does not carry and this machine
  has not installed, for which a reduced detail is composed from the resident tap inventory alone
- WHEN the catalog snapshot, catalog search and catalog detail lookup are queried for it
- THEN it remains absent from the snapshot and from search results, and the detail lookup still returns
  the ordinary not-found result
- AND no catalog record exists for it, synthesized or otherwise, and the composed detail carries no
  value the catalog publishes
- Verification: `unit`

#### Scenario: A colliding selection resolves to the catalog's own record and creates nothing

- GIVEN the catalog carries a package, an installed third-party tap publishes the same `(kind, name)`,
  and the identity the tap surface offers for that row is the bare one
- WHEN that identity is resolved through the ordinary catalog detail lookup with the tap inventory
  resident
- THEN the lookup returns the catalog's own record — byte-identical to the record the same lookup
  returns with no tap inventory resident — so nothing about the tap package reached it
- AND the snapshot and the index are unchanged: the record count is the catalog's own, the catalog
  search results for that query are identical to those returned with no tap inventory present, and no
  record exists for any package the catalog does not cover
- Verification: `unit`

## Notes for archive

- **The verification-class table above is NOT promoted.** `openspec/specs/package-detail/spec.md`
  carries no `## Verification classes` table today, and this delta adds none: the table is delta-local
  provenance and only the per-scenario inline `- Verification:` line promotes with the requirement. The
  class names used across this change are the established `unit` and `unit-app`
  (`openspec/specs/app-updates/spec.md:16-17`); no new class is introduced.
- The MODIFIED block replaces **PD6** in place. PD1–PD5, PD7 and PD8 are byte-identical, and PD6's
  three existing scenarios — including the one m10 added — are reproduced byte-identical.
  `openspec/specs/package-detail/spec.md` carries no `<!-- PD# -->` markers, so PD6 is an ordinal label
  used in prose, not a token in the file; the block is matched by its heading.
- **PD8 needs no delta.** An installed tap hit hands off to the m10 receipt-backed detail, where PD8's
  marker already applies unchanged. Round 6 gives an unambiguous **not-installed** hit a detail of its
  own that *does* render a tap-of-origin fact — and PD8 still needs no delta, because its marker is a
  fact about a **receipt's** origin and a package this machine has not installed has none. `package-search`
  PS8 requires that pane to present the marker's **absence**, which is PD8's own positive-only rule
  applied rather than amended.
- The added paragraph is deliberately symmetric with m10's: same four negations (no catalog record,
  nothing added to the snapshot or search, no catalog value consulted, no additional brew invocation),
  plus the one this change needs — composed above the index, never pushed into it.
- **Round 7 adds no permission, only a clarification.** The colliding-selection sentence describes the
  catalog answering for a package **it covers**, by the same lookup it has always answered with. Nothing
  in the round makes a tap package reachable through the snapshot, the index or the detail lookup; the
  membership carve-out is unchanged and no new catalog read is granted. The added scenario proves the
  record returned is byte-identical to the one the same lookup returns with **no tap inventory
  resident**, which is the strongest available form of "the tap contributed nothing".
