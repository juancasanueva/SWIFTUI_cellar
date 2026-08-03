# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (14 requirements / 54 scenarios).

Delta summary: **1 MODIFIED requirement — 6 scenarios (5 carried forward unchanged, 1 added)**. The
MODIFIED requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED,
REMOVED or RENAMED.

The requirement fixes selection order *because that order determines submission order*, but not for a
set added at once: a bulk add currently enters the selection in flat inventory order, so operations
are submitted in an order the user never saw. Settled: the order the list displays them, top to
bottom across whatever sections the list renders — promoting M2-3's design ruling into a durable
scenario rather than a code comment. (The scenario deliberately does not enumerate section names:
the section set belongs to the view and has already changed once.) This slice adds **no** bulk verb, so the exhaustive "only upgrade and uninstall"
scenario is carried forward unchanged. The fan-out into brew invocations remains owned by
`package-mutation`.

## MODIFIED Requirements

### Requirement: Multi-select is explicit, ordered, and offered only for bulk-eligible verbs

The installed list MUST expose a selection of zero or more packages. The selection MUST preserve the
order in which packages were selected, because that order determines the order their operations are
submitted. A package that leaves the inventory MUST leave the selection at the next refresh, so no
action can be submitted for a package the app no longer lists. Bulk affordances MUST be offered for
upgrade and uninstall only; pin, unpin, snooze, favorite and note MUST offer no bulk affordance, and
a bulk control that cannot act on the current selection MUST be unavailable rather than inert.

When more than one package enters the selection in a single action — select-all, or any multi-package
add — they MUST enter it in the order the list displays them: section by section from top to bottom,
and within each section in that section's displayed order. They
MUST NOT enter it in the underlying inventory's order. Because selection order determines submission
order, the order the resulting operations are submitted MUST therefore match the order the user sees.
(Previously: the requirement fixed selection order only for packages selected one at a time; the
order in which a bulk add entered them was unspecified, so it followed flat inventory order rather
than displayed order.)

#### Scenario: Selection preserves order

- GIVEN an installed list containing `git`, `wget` and `iterm2`
- WHEN `wget`, then `iterm2`, then `git` are selected
- THEN the selection is reported in the order `wget`, `iterm2`, `git`

#### Scenario: A bulk add enters the selection in displayed order

- GIVEN an installed list whose inventory order is `git`, `pcre2`, `iterm2`, and whose displayed
  order — as rendered by its sections, top to bottom — is `iterm2`, then `git`, then `pcre2`
- WHEN all three are added to the selection in one bulk add
- THEN the selection is reported in the order `iterm2`, `git`, `pcre2`
- AND their operations are submitted in that same order, not in inventory order

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
