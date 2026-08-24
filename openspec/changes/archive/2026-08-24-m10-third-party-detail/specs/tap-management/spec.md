# Delta for tap-management

Existing capability — `openspec/specs/tap-management/spec.md` (**13 requirements / 57 scenarios**,
established by `2026-08-05-m3-taps` and amended by `2026-08-23-m7-tap-trust` and
`2026-08-24-m9-per-package-trust`). This delta is **1 MODIFIED, 0 added, 0 removed, 0 renamed**: the
modified block keeps all **9** scenarios it carries today byte-identical and adds **1**, taking the
capability to **13 requirements / 58 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. The MODIFIED block is a whole-block replacement copied from the main spec and then edited; it
is a strict superset of the text it replaces, and the only edited sentence is the final one of the
withheld-tap paragraph.

**Why this narrowing.** TM5 ends today with "Tap packages MUST NOT enter the catalog snapshot, catalog
search, or catalog detail; PD6 remains unchanged and selection MUST NOT create a third-party detail
fallback." In context, "selection" is tap-package row selection on the Taps surface, and the
prohibition pairs with "MUST NOT enter … catalog detail" — selecting a tap package must not fabricate a
catalog record for it. m10 fabricates nothing and adds no Taps navigation. But the bare phrase is broad
enough to be read as a blanket ban on any detail for a tap package, and the m9 archive already reads it
that way. This delta states the clause's meaning so the boundary is documented rather than argued.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m10-third-party-detail/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour | `swift test --package-path Packages/CellarCore` | **1** |

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

The inventory MUST be filterable by package name and kind. A large inventory MUST remain usable by
presenting only the filtered/visible rows needed at a time rather than requiring every row to be
presented eagerly.
(Previously: installed status came only from an exact `InstalledPackage.tap` equality, so a package
installed from an untrusted tap — whose tap brew withholds — was *mandated* to read “Not installed.”,
a false statement about this Mac.)
(Previously: the catalog paragraph ended “…and selection MUST NOT create a third-party detail
fallback.”, a bare phrase broad enough to read as a blanket ban on any detail for a tap package,
including one built solely from the installed receipt.)

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

## Notes for archive

- **The verification-class table above is NOT promoted.** `openspec/specs/tap-management/spec.md`
  carries no `## Verification classes` table today, and this delta adds none: the table is delta-local
  provenance and only the per-scenario inline `- Verification:` lines promote with the requirement.
  The class names used across this change are the established `unit` and `unit-app`
  (`openspec/specs/app-updates/spec.md:16-17`); no new class is introduced.
- The MODIFIED block replaces **TM5** in place, under its existing `<!-- TM5 -->` marker. TM1–TM4 and
  TM6–TM13 are byte-identical, and TM5's nine existing scenarios are reproduced byte-identical.
- **TM1 is unchanged and was mis-cited by m9.** The m9 archive states in at least three places that TM1
  forbids a third-party detail fallback. TM1 is a one-invocation rule about *tap* detail acquisition;
  the clause is TM5's. TM1's genuine constraint on m10 — no additional brew invocation may be
  introduced to complete a detail — is honoured and is asserted by the added scenario.
- The narrowed clause changes no shipped behaviour: no Taps navigation is added, and the
  **Show in Installed** handoff already lands on the branch this change fills in.
