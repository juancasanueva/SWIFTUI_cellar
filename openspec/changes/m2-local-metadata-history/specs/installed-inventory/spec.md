# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (11 requirements / 39 scenarios).

Delta summary: **1 MODIFIED requirement / 3 ADDED requirements — 22 scenarios**. The MODIFIED
requirement is reproduced in full so the archive step loses nothing. Nothing is REMOVED or RENAMED.

What changes here:

1. **Favorites compose as a filter**, exactly as the installed-state filters already do, and note
   text stays out of every search index (settled: favorites are a filter bar entry, not a sidebar
   section; notes are not searchable). This extends the requirement that already owns filter
   composition rather than competing with it.
2. **Snoozed packages leave the outdated section and its count** — a new rule that does not alter the
   existing self-updating-cask derivation, so it is ADDED, not folded into it.
3. **Multi-select** becomes part of the installed list's observable model, and bulk affordances are
   restricted to upgrade and uninstall (pin, unpin, snooze, favorite and note are not bulk-eligible).
4. **A bulk action's label counts exactly the set it submits** — M2-2 follow-up 1: the label counted
   the dependency-filtered entries while the submission filtered the whole inventory, so the button
   could promise fewer upgrades than it submitted.

Storage of favorites, notes and snoozes, and the snooze badge rule itself, are owned by
`local-package-metadata` and referenced here, never restated. The fan-out of a bulk selection into
brew invocations is owned by `package-mutation`.

## MODIFIED Requirements

### Requirement: Installed-state filters are composed, never pushed into the search index

Browse MUST offer installed, not-installed and outdated filters. Each MUST be answered by
intersecting catalog query results with membership sets supplied by this capability; the catalog
query contract MUST NOT gain an installed, not-installed or outdated predicate. The outdated filter
MUST use the same outdated derivation as the installed list, so self-updating casks are excluded
from it too. When the inventory is unavailable or empty, the filters MUST render disabled and MUST
NOT alter the results a user would otherwise see.

While browse is showing an installed-driven mode — installed or outdated — the catalog-only filter
controls (package kind, deprecated, disabled) MUST either apply to that mode's visible results
exactly as they apply to catalog results, or be rendered disabled for that mode. A control that is
enabled but cannot change the visible results is forbidden: every enabled control MUST be honoured,
and every control that is not honoured MUST be visibly unavailable.

A favorites filter MUST be offered in the same filter bar and MUST be composed on exactly the same
terms: it is answered by intersecting results with the favorite membership set supplied by
`local-package-metadata`, and the catalog query contract MUST NOT gain a favorite predicate. It MUST
be combinable with the other filters rather than replacing them, and MUST render disabled when no
metadata is available. Locally stored note text MUST NOT be added to any search index and MUST NOT be
matched by the installed list's search or by catalog search.
(Previously: the requirement governed the three installed-state filters and the catalog-only controls
beside them; there was no favorites filter, and nothing forbade note text from entering a search
index.)

#### Scenario: The installed filter narrows browse results

- GIVEN a catalog containing `wget` and `curl`, and an inventory containing only `wget`
- WHEN browse results are filtered to installed
- THEN only `wget` remains

#### Scenario: The not-installed filter is the complement

- GIVEN the same catalog and inventory
- WHEN browse results are filtered to not-installed
- THEN only `curl` remains

#### Scenario: The outdated filter excludes self-updating casks

- GIVEN an inventory with one outdated formula and one self-updating cask behind its published
  version
- WHEN browse results are filtered to outdated
- THEN only the formula remains

#### Scenario: With no inventory the filters are disabled and results are unchanged

- GIVEN brew detection reports absent and the inventory is empty
- WHEN browse is opened and a query runs
- THEN the installed, not-installed and outdated filters are disabled
- AND the results are identical to the same query with no installed-state filtering

#### Scenario: The catalog filter set still declares no installed predicate

- GIVEN the catalog query's declared filter set
- WHEN it is enumerated
- THEN it contains no installed, not-installed, outdated or favorite predicate

#### Scenario: No catalog filter control is enabled but inert under the installed mode

- GIVEN browse in the installed mode over an inventory holding one formula and one cask, one of them
  deprecated
- WHEN the kind, deprecated and disabled controls are inspected
- THEN each control is either reported unavailable for that mode, or changes the visible results
  when it is applied

#### Scenario: The outdated mode obeys the same rule

- GIVEN browse in the outdated mode over an inventory holding one outdated formula and one outdated
  cask
- WHEN the kind control is applied to casks only
- THEN either the control was reported unavailable for that mode, or only the cask remains

#### Scenario: The favorites filter narrows the list

- GIVEN an inventory containing `wget` and `curl`, with only `wget` marked favorite
- WHEN the favorites filter is applied
- THEN only `wget` remains

#### Scenario: The favorites filter composes with the other filters

- GIVEN an inventory of one outdated favorite, one up-to-date favorite and one outdated
  non-favorite
- WHEN the favorites and outdated filters are both applied
- THEN only the outdated favorite remains

#### Scenario: With no metadata the favorites filter is disabled and results are unchanged

- GIVEN an inventory and no metadata store
- WHEN the filter bar is inspected and a query runs
- THEN the favorites filter is disabled
- AND the results are identical to the same query with no favorites filtering

## ADDED Requirements

### Requirement: Snoozed packages leave the outdated section and its count

A package with a snooze in effect — as defined by `local-package-metadata`, meaning the version
currently offered for it still **equals** the stored snoozed version — MUST be absent from the
outdated set, MUST NOT contribute to the outdated count or badge, and MUST be excluded from the
outdated browse filter on exactly the same terms, so the list and the filter cannot disagree. As soon
as the offered version differs from the stored snoozed one — newer, older, or differing only by a
revision suffix — the package MUST return to the outdated set, the count and the filter without user
action. This capability MUST NOT order or precedence-compare version strings to decide that; it
consumes the equality rule owned by `local-package-metadata`. A snooze MUST NOT remove the package
from the installed list itself.

#### Scenario: A snoozed package is absent from the set and the count

- GIVEN two outdated formulae, one of them snoozed at the version it is outdated toward
- WHEN the outdated set and the outdated count are read
- THEN only the non-snoozed formula is in the set
- AND the count is 1

#### Scenario: A changed offered version returns it to the set and the count

- GIVEN a formula snoozed at version `1.2.3`
- WHEN the offered version becomes `1.3.0`, and separately `1.2.3_1`, and the inventory refreshes
- THEN the formula is in the outdated set again and the count includes it in both cases
- AND no user action was required

#### Scenario: The outdated browse filter agrees with the outdated list

- GIVEN an inventory with one snoozed outdated package and one unsnoozed outdated package
- WHEN browse results are filtered to outdated
- THEN exactly the packages in the outdated set remain, and the snoozed one is absent

#### Scenario: A snooze does not hide the package from the installed list

- GIVEN a snoozed outdated package
- WHEN the installed list is read with default filters
- THEN the package is listed with its installed version

### Requirement: Multi-select is explicit, ordered, and offered only for bulk-eligible verbs

The installed list MUST expose a selection of zero or more packages. The selection MUST preserve the
order in which packages were selected, because that order determines the order their operations are
submitted. A package that leaves the inventory MUST leave the selection at the next refresh, so no
action can be submitted for a package the app no longer lists. Bulk affordances MUST be offered for
upgrade and uninstall only; pin, unpin, snooze, favorite and note MUST offer no bulk affordance, and
a bulk control that cannot act on the current selection MUST be unavailable rather than inert.

#### Scenario: Selection preserves order

- GIVEN an installed list containing `git`, `wget` and `iterm2`
- WHEN `wget`, then `iterm2`, then `git` are selected
- THEN the selection is reported in the order `wget`, `iterm2`, `git`

#### Scenario: Deselecting removes exactly one package

- GIVEN a selection of three packages
- WHEN the second is deselected
- THEN the selection holds the other two, in their original relative order

#### Scenario: A package that leaves the inventory leaves the selection

- GIVEN a selection containing `wget`
- WHEN a refresh produces an inventory that no longer contains `wget`
- THEN the selection no longer contains `wget`

#### Scenario: Only upgrade and uninstall are offered for a selection

- GIVEN a non-empty selection
- WHEN the bulk controls exposed for it are enumerated
- THEN upgrade and uninstall are present
- AND no bulk pin, unpin, snooze, favorite or note control is present

#### Scenario: An empty selection offers no enabled bulk control

- GIVEN an empty selection
- WHEN the bulk controls are inspected
- THEN every bulk control is unavailable

### Requirement: A bulk action's label counts exactly the set it submits

Any control that announces how many packages a bulk action will affect MUST derive that number from
the same projection the action submits. The label and the submitted set MUST be computed from one
source: applying the same filters, the same dependency toggle and the same snooze exclusion. It MUST
be impossible for the control to announce one number and submit a different set.

#### Scenario: The label matches the submitted set under the default filters

- GIVEN an inventory of outdated on-request and outdated dependency-only packages, with the
  dependency toggle off
- WHEN the bulk-upgrade control's announced count is read and the action is then submitted
- THEN the number of operations submitted equals the announced count

#### Scenario: Toggling the dependency filter moves both together

- GIVEN the same inventory
- WHEN the dependency toggle is turned on and the announced count is read and the action submitted
- THEN the announced count changed
- AND the number of operations submitted still equals the announced count

#### Scenario: Snoozed packages are excluded from both the label and the submission

- GIVEN an inventory of three outdated packages, one of them snoozed
- WHEN the bulk-upgrade control's announced count is read and the action is submitted
- THEN the announced count is 2
- AND exactly two operations are submitted, neither naming the snoozed package
