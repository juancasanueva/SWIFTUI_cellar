# Delta for package-detail

Existing capability — `openspec/specs/package-detail/spec.md` (**8 requirements / 30 scenarios**,
established by `2026-08-01-m1-catalog-browse`, amended by `2026-08-06-m5-catalog-inspection` and
`2026-08-24-m9-per-package-trust`). This delta is **1 MODIFIED, 0 added, 0 removed, 0 renamed**: the
modified block keeps both scenarios it carries today **byte-identical** and adds **1 scenario**, taking
the capability to **8 requirements / 31 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. The MODIFIED block is a whole-block replacement copied from the main spec and then edited; it
is a strict superset of the text it replaces. The only textual change is **one added paragraph** drawing
the catalog/receipt boundary. In particular the clause "MUST NOT appear in search results" is reproduced
verbatim: search absence is not weakened by one character.

**This delta lands in the first work unit (proposal risk R1).** Read literally, PD6 constrains the
catalog — the snapshot, search results, and the catalog detail lookup — and a receipt-backed rendering
violates none of them. But the `2026-08-24-m9-per-package-trust` archive reads PD6 as a blanket
prohibition in three places ("this change adds no third-party detail fallback"). Shipping m10 against an
unamended PD6 would leave a documented contradiction in the repository, so the boundary is drawn before
any code lands.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m10-third-party-detail/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour | `swift test --package-path Packages/CellarCore` | **1** |

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
(Previously: the requirement stated only the catalog-scope clauses, and was being cited as a blanket ban
on any third-party detail rendering, including one built solely from the installed receipt.)

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

## Notes for archive

- **The verification-class table above is NOT promoted.** `openspec/specs/package-detail/spec.md`
  carries no `## Verification classes` table today, and this delta adds none: the table is delta-local
  provenance and only the per-scenario inline `- Verification:` line promotes with the requirement.
  The class names used across this change are the established `unit` and `unit-app`
  (`openspec/specs/app-updates/spec.md:16-17`); no new class is introduced.
- The MODIFIED block replaces **PD6** in place. PD1–PD5, PD7 and PD8 are byte-identical, and PD6's two
  existing scenarios are reproduced byte-identical.
- **PD8 needs no delta.** m10 activates it rather than changing it: the receipt-backed detail is the
  first surface to render a tap-of-origin fact for a package the catalog does not carry, so the marker
  finally has its anchor. PD8's exact-identity rule is what keeps the withheld-tap case marker-free, and
  the marker still is not a field of this capability's projection.
- Record in provenance that the m9 archive's citation of **TM1** as the source of the
  "no third-party detail fallback" prohibition is a **mis-citation**: the clause is **TM5**'s. TM1 is a
  one-invocation rule about tap-detail acquisition. TM1's real constraint on m10 — no additional brew
  invocation may be introduced to complete a detail — is honoured and asserted.
