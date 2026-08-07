# Delta for local-package-metadata

**2 MODIFIED** requirements, each replaced as a whole block that is a **strict superset** of the text
it replaces, adding **5 scenarios** in total. Nothing is ADDED, REMOVED or RENAMED.
7 requirements / 22 scenarios → **7 requirements / 27 scenarios**.

Snooze behaviour does not change. Equality is still the whole rule: exact string comparison, no
ordering, no clock, no duration. What changes is that a snooze can now be recorded for **several
packages in one user action** (decision **D2**, Engram `#7532`), which raises two questions the
shipped text did not answer:

1. **Whose version does each row record?** Its own. N packages are outdated toward N *different*
   version strings; a batch that shared one version would silently mis-scope N−1 snoozes and, worse,
   suppress badges for versions those packages were never outdated toward. LPM4 gains the rule and
   three scenarios.
2. **Can a new caller evade the no-comparator guard?** The guard is deliberately **file-scoped and
   enumerated exhaustively** rather than target-scoped. A bulk-snooze surface living outside this
   capability's own target is a new snooze caller that the enumerated list does not name, so the
   guarantee would hold vacuously for it. LPM5 gains the scope rule and one scenario. The guard is
   **extended, not weakened**: the comment-stripped source scan, the forbidden comparator tokens and
   the positive `snoozedVersion == candidate` anchor all stay.

The copy rule is stated as a requirement rather than left to a surface, because "snooze" is the one
verb in the app whose ordinary English meaning is a *duration* and whose implementation deliberately
is not.

## MODIFIED Requirements

<!-- LPM4 -->
### Requirement: A snooze is scoped to a version, never to a duration

Snoozing a package MUST record the exact version the snooze applies to — the version the package is
currently outdated toward — and nothing else. The capability MUST NOT accept, store or require a
duration, an expiry date, or any reading of the clock, so snooze behaviour is reproducible without a
clock seam. Snoozing an already-snoozed package MUST replace the stored version rather than
accumulate a second snooze. Unsnoozing MUST remove the stored snooze entirely.

Snoozing more than one package in a single user action MUST record **one snooze per package, each
naming that package's own currently offered version**. Such an action MUST NOT record a shared
version, MUST NOT reuse one package's offered version for another, and MUST NOT introduce a batch
identity, a group record, or any notion of a snooze that spans packages: the stored result MUST be
indistinguishable from having snoozed each package individually, in any order. A package in the batch
with no offered version to snooze toward MUST record nothing, rather than a placeholder, an empty
string or a neighbour's version. The action MUST NOT compare, order or rank the versions it records.

Copy that offers a snooze — for one package or for many — MUST NOT state or imply a duration, a
period, an expiry, or a "remind me later" interval. It MUST state what the snooze actually does: it
lasts until a different version is offered. A stored snooze's creation timestamp is **provenance
only**: it MUST NOT be read as policy, MUST NOT govern when a snooze ends, and MUST NOT reach any
projection that decides whether a badge is suppressed.
(Previously: the requirement governed snoozing a package and said nothing about snoozing several
packages in one action, nor about the copy that offers a snooze.)

#### Scenario: Snoozing records the version it applies to

- GIVEN an installed package outdated toward published version `1.2.3`
- WHEN it is snoozed
- THEN the stored snooze names version `1.2.3`

#### Scenario: A snooze carries no time component

- GIVEN a stored snooze
- WHEN its stored fields are enumerated
- THEN they carry no duration, no expiry and no timestamp that governs when the snooze ends

#### Scenario: Re-snoozing replaces rather than accumulates

- GIVEN a package snoozed at version `1.2.3` that is now outdated toward `1.3.0`
- WHEN it is snoozed again
- THEN exactly one snooze is stored for it, naming `1.3.0`

#### Scenario: Snoozing many records each package's own version

- GIVEN three outdated packages offered `1.2.3`, `2026-08-01` and `4.0.0_1` respectively
- WHEN all three are snoozed in one action
- THEN three snoozes are stored, naming `1.2.3`, `2026-08-01` and `4.0.0_1` respectively
- AND no shared version, batch identity or group record was stored

#### Scenario: A multi-package snooze is indistinguishable from individual ones

- GIVEN the same three packages
- WHEN they are snoozed in one action, and separately snoozed one at a time in a different order
- THEN the stored snoozes are equal in both cases, field for field apart from provenance

#### Scenario: A package with nothing to snooze toward records nothing

- GIVEN a batch containing one outdated package and one package with no offered version
- WHEN the batch is snoozed
- THEN exactly one snooze is stored, naming the outdated package's version
- AND no placeholder, empty or borrowed version was stored for the other

#### Scenario: The snooze copy implies no duration

- GIVEN every copy that offers a snooze, for one package and for many
- WHEN it is read
- THEN none of it states or implies a duration, a period, an expiry or an interval
- AND each states that the snooze lasts until a different version is offered

<!-- LPM5 -->
### Requirement: A snooze suppresses the outdated badge until the offered version changes

While a package has a stored snooze, the outdated badge for that package MUST be suppressed for
exactly as long as the version currently offered for it **equals** the stored snoozed version,
compared as an exact string. Any different offered value — newer, older, or differing only by a
revision suffix — MUST revive the badge, without user action and without the snooze having to be
cleared manually. The capability MUST NOT order, rank or precedence-compare Homebrew version strings,
and MUST NOT depend on any version comparator: equality is the whole rule. Unsnoozing MUST restore
the badge immediately, on the same refresh. Suppression MUST be a projection over the inventory's
outdated state and the stored snooze: it MUST NOT alter the inventory's own outdated derivation, and
it MUST NOT hide the package from the Installed list.

A strict-SemVer comparator MAY exist elsewhere in the app, confined to `vulnerability-scanning`. It
MUST remain structurally unreachable from this capability: this capability's sources MUST declare no
dependency on the module that owns it, MUST NOT import it, and MUST NOT accept a comparison result,
comparator, ordering closure or "is newer" value from it in any snooze input, stored field or
projection. The absence MUST stay enforced structurally rather than by convention: the existing
structural guard MUST continue to scan this capability's real sources with comments stripped, MUST
continue to assert the same forbidden comparator tokens absent and to carry its positive equality
anchor so the scan cannot pass vacuously, and MUST additionally assert that no import of, or
reference to, the comparator-owning module appears in those sources. The guard's scope narrows from
"no comparator exists in the repository" to "no comparator is reachable from this capability"; it
MUST NOT be deleted, weakened to a comment, or satisfied by an allow-list.

Because that scope is enumerated exhaustively rather than derived from a target boundary, it MUST
cover **every** source that participates in recording or projecting a snooze, including a source
outside this capability's own target — such as a surface that snoozes several packages in one action.
A new snooze caller MUST NOT be able to evade the guarantee by living outside the enumerated list:
adding such a caller MUST either place it in the guard's scope, or route its snoozes only through a
source already in that scope. A caller outside the scope that constructs, compares or orders a version
string itself MUST fail the guard rather than pass it silently.
(Previously: the rule was identical for snooze behaviour, but the no-comparator guarantee was
repository-wide; it is now scoped to this capability's reachability, because `m4-security`
introduces a strict-SemVer comparator inside `vulnerability-scanning`. This revision adds only the
rule that the enumerated scope must follow every snooze caller, including one outside this
capability's target.)

#### Scenario: The badge is suppressed while the offered version is unchanged

- GIVEN a package snoozed at version `1.2.3` and still outdated toward `1.2.3`
- WHEN its badge state is read
- THEN no outdated badge is shown for it

#### Scenario: A newer offered version revives the badge

- GIVEN a package snoozed at version `1.2.3`
- WHEN the offered version becomes `1.3.0` and the inventory refreshes
- THEN the outdated badge is shown again
- AND no user action was required to clear the snooze

#### Scenario: A revision-suffixed or older offered version also revives the badge

- GIVEN a package snoozed at version `1.2.3`
- WHEN the offered version is `1.2.3_1`, and separately an older `1.2.2`
- THEN the outdated badge is shown again in both cases — the accepted, visible false positive of an
  equality rule
- AND no ordering comparison of version strings was performed to reach either result

#### Scenario: Unsnoozing restores the badge immediately

- GIVEN a snoozed package whose badge is suppressed
- WHEN the snooze is removed
- THEN the outdated badge is shown on the next read, with no refresh of the inventory required

#### Scenario: A snoozed package is still listed as installed

- GIVEN a snoozed, outdated package
- WHEN the Installed list is read with default filters
- THEN the package is listed with its installed version

#### Scenario: The security comparator is structurally unreachable from snooze

- GIVEN a strict-SemVer comparator exists in the module owning `vulnerability-scanning`
- WHEN the structural guard scans this capability's sources with comments stripped, and its declared
  dependencies are enumerated
- THEN the forbidden comparator tokens are absent, the positive equality anchor is present, and
  neither an import of nor a reference to the comparator-owning module appears
- AND snooze behaviour is byte-identical to its behaviour before that comparator existed

#### Scenario: A snooze caller outside this capability cannot evade the guard

- GIVEN a surface outside this capability's own target that records snoozes for several packages in
  one action
- WHEN the structural guard's enumerated scope is read
- THEN that surface is either named in the scope, or records its snoozes only through a source that is
- AND the forbidden comparator tokens are absent from every source the scope names
