# Delta for Local Package Metadata

## MODIFIED Requirements

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
(Previously: the rule was identical for snooze behaviour, but the no-comparator guarantee was
repository-wide; it is now scoped to this capability's reachability, because `m4-security`
introduces a strict-SemVer comparator inside `vulnerability-scanning`.)

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
