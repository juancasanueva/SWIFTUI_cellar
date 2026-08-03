# installed-inventory

Acquiring the installed-package snapshot from a single `brew info --installed --json=v2` probe,
projecting and decoding it off the main actor, deriving outdated / pinned / on-request state,
classifying self-updating casks, joining the snapshot to the catalog, composing installed-state
filters for browse, keeping the inventory fresh under external change, and behaving correctly when
brew is absent. Owned by `Packages/CellarCore` target `BrewClient` — the only target that sees both
`BrewProcess` and `Catalog`, one-directionally.

## Requirements

### Requirement: The installed snapshot comes from one probe, decoded off the main actor

An installed-inventory refresh MUST acquire its data from exactly one `brew info --installed
--json=v2` invocation. Outdated state, pin state, on-request state, install timestamps and the
current published version MUST be derived from that single payload; the system MUST NOT spawn a
second brew invocation (in particular `brew outdated`, `brew outdated --greedy`, or
`brew list --pinned`) to answer them. Decoding MUST run off the main actor and MUST project the
payload down to the fields the inventory uses, so the main actor stays responsive while a snapshot
of realistic size (approximately 160 records today, several hundred in the worst case) is decoded.

#### Scenario: One invocation per refresh

- GIVEN a fake process launcher recording every invocation
- WHEN one inventory refresh completes
- THEN exactly one brew invocation was recorded
- AND its arguments are `info --installed --json=v2`

#### Scenario: Derived facts require no extra invocation

- GIVEN a snapshot payload carrying outdated, pinned and on-request records
- WHEN outdated, pinned and dependency-only state are read from the inventory
- THEN they are all answered
- AND still exactly one brew invocation was recorded

#### Scenario: The main actor stays responsive during decode

- GIVEN a payload of realistic size
- WHEN it is decoded into the inventory projection
- THEN other main-actor work submitted after the decode starts runs to completion before the decode
  finishes

### Requirement: Asymmetric formula and cask installation shapes both decode

Decoding MUST accept the payload's asymmetric shapes: a formula's installed data is an array of keg
records, and a cask's installed data is a plain version string. A formula with more than one
installed keg MUST be represented with all of its kegs, never truncated to one and never dropped. A
cask's `auto_updates` field is tri-state (`true`, `null`, absent, never `false` in observed
payloads) and MUST be preserved as "declared" versus "not declared" at decode time rather than
folded into a plain boolean.

#### Scenario: A single-keg formula decodes

- GIVEN a formula record whose installed array holds one keg
- WHEN the payload is decoded
- THEN the formula appears in the inventory with that keg's version and install time

#### Scenario: A multi-keg formula keeps every keg

- GIVEN a formula record whose installed array holds two kegs with different versions
- WHEN the payload is decoded
- THEN the formula appears once with both installed versions represented
- AND neither keg is dropped

#### Scenario: A cask's string installed version decodes

- GIVEN a cask record whose installed field is the string `1.2.3`
- WHEN the payload is decoded
- THEN the cask appears in the inventory with installed version `1.2.3`

#### Scenario: An undeclared auto-update flag is distinguishable from a declared one

- GIVEN one cask record with `auto_updates` true and one with `auto_updates` null
- WHEN both are decoded
- THEN the first is classified as self-updating and the second is not
- AND the null value is recorded as "not declared", not as an explicit false

### Requirement: On-request and dependency-only are derived, and the default view is on-request

The payload carries no `installed_as_dependency` field. "Installed as a dependency" MUST therefore
be derived as the absence of an on-request marker on the installed record. The default installed
view MUST show on-request packages only; dependency-only packages MUST be shown only when the
dependency toggle is on. A record that carries no on-request signal at all MUST be treated as
on-request, so nothing a user deliberately installed can be hidden by the default view.

#### Scenario: The default view hides dependency-only formulae

- GIVEN an inventory of one on-request formula and one dependency-only formula
- WHEN the installed list is read with default filters
- THEN only the on-request formula is listed

#### Scenario: The toggle reveals dependency-only formulae

- GIVEN the same inventory
- WHEN the dependency toggle is on
- THEN both formulae are listed
- AND each exposes whether it was installed on request

#### Scenario: A record with no on-request signal is treated as on-request

- GIVEN an installed cask, whose records carry no on-request marker
- WHEN the installed list is read with default filters
- THEN the cask is listed

### Requirement: Auto-updating casks never count as outdated

Outdated state MUST be taken from the snapshot's own outdated flag, which already applies brew's
default auto-updates exclusion. A cask classified as self-updating MUST NOT be reported as outdated,
MUST NOT contribute to any outdated count or badge, and MUST be presented separately from the
ordinary outdated set — even when a newer version exists for it. A cask that is not self-updating
MUST be reported as outdated on exactly the same terms as a formula.

#### Scenario: An outdated formula is reported and counted

- GIVEN an installed formula whose snapshot record is outdated
- WHEN the outdated set is read
- THEN the formula is in it and the outdated count includes it

#### Scenario: A self-updating cask behind its published version is never outdated

- GIVEN an installed cask declaring auto-updates, installed `1.2.3`, published version `1.3.1`,
  whose snapshot outdated flag is false
- WHEN the outdated set and the outdated count are read
- THEN the cask is absent from the set
- AND the count does not include it
- AND the cask is classified as self-updating

#### Scenario: A cask without auto-updates is outdated on the same terms as a formula

- GIVEN an installed cask that does not declare auto-updates and whose snapshot record is outdated
- WHEN the outdated set is read
- THEN the cask is in it and the outdated count includes it

### Requirement: A self-updating cask's newer version is derived from the same probe

For a cask classified as self-updating, the inventory MUST expose whether a newer version exists,
derived from the same single payload by comparing the installed version against the published
version on that record. Producing this signal MUST NOT spawn any additional brew invocation. The
signal MUST remain informational: it MUST NOT feed the outdated set, the outdated count, or an
outdated badge.

#### Scenario: The newer-version signal is derived without a second invocation

- GIVEN a self-updating cask with installed `1.2.3` and published version `1.3.1`
- WHEN the inventory is refreshed and the cask is inspected
- THEN it reports that a newer version exists
- AND exactly one brew invocation was recorded

#### Scenario: Matching versions produce no signal

- GIVEN a self-updating cask with installed `1.3.1` and published version `1.3.1`
- WHEN the cask is inspected
- THEN it reports no newer version
- AND it is still absent from the outdated set

### Requirement: Pin state and install date come from the snapshot

The inventory MUST expose pin state, and the pinned version when one is recorded, for both formulae
and casks, read from the snapshot rather than from a separate pin listing. It MUST expose an install
date derived from the record's install timestamp, interpreted as Unix epoch seconds, for both kinds.

#### Scenario: Pin state is exposed for both kinds without an extra invocation

- GIVEN a pinned formula and a pinned cask in the payload
- WHEN their pin state is read
- THEN both report pinned with their recorded pinned version
- AND exactly one brew invocation was recorded

#### Scenario: Install dates come from the recorded timestamps

- GIVEN a formula keg record and a cask record each carrying an epoch-seconds install timestamp
- WHEN their install dates are read
- THEN each date equals its recorded timestamp interpreted as epoch seconds

### Requirement: The catalog join happens above both packages

Installed records MUST be joined to catalog records on the package identity already used by the
catalog — the `(kind, name)` pair — reusing that identity rather than introducing a second one. An
installed package with no matching catalog record (a tap-only or unpublished package) MUST still be
listed with everything the snapshot knows about it, never hidden. The join MUST live above both the
catalog and the brew-process layers: the catalog MUST NOT gain a dependency on brew process
execution, so catalog sync and search continue to work with brew absent.

#### Scenario: A matched package carries catalog metadata

- GIVEN an installed formula `wget` and a catalog record for formula `wget` with a description
- WHEN the joined inventory entry is read
- THEN it carries the installed version and the catalog description

#### Scenario: An unmatched installed package is still listed

- GIVEN an installed formula from a third-party tap with no catalog record
- WHEN the installed list is read
- THEN the formula is listed with its snapshot data and no catalog metadata

#### Scenario: The catalog target does not depend on the brew-process target

- GIVEN the package graph of `Packages/CellarCore`
- WHEN the dependencies of the catalog target are enumerated
- THEN they contain no brew-process target, directly or transitively

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

### Requirement: Brew absent or invalid yields an empty inventory and read-only guidance

When brew detection reports absent, invalid or a missing configured path, the inventory MUST be
empty, MUST NOT attempt a probe, MUST NOT throw or block, and MUST surface read-only guidance
instead of an error state. Catalog browse and search MUST be unaffected. When brew later becomes
available, the inventory MUST populate without restarting the app.

#### Scenario: Absent brew produces an empty inventory with guidance

- GIVEN brew detection reports absent
- WHEN the inventory is read
- THEN it is empty, nothing is thrown, and install guidance is available
- AND no brew process was spawned

#### Scenario: An invalid configured path is guidance, not failure

- GIVEN brew detection reports an invalid configured path
- WHEN the inventory is read
- THEN it is empty and the rejection reason is available as read-only guidance
- AND no brew process was spawned

#### Scenario: The inventory populates when brew appears

- GIVEN an empty inventory because detection reported absent
- WHEN detection transitions to a valid installation and a refresh runs
- THEN the inventory reports the installed packages from the resulting snapshot

### Requirement: External changes invalidate the inventory, debounced and coalesced

An external change to the installed packages MUST be reflected without user action. The change
signal MUST be treated purely as an invalidation trigger: its contents MUST NOT be parsed to derive
inventory state — a re-snapshot is always taken instead. Bursts of signals MUST be coalesced on an
injected clock so that a burst within the quiet window causes exactly one re-snapshot. While a
Cellar-initiated mutation is in flight, signals MUST be suppressed, and exactly one re-snapshot MUST
be taken at that mutation's terminal outcome. Overlapping refresh requests MUST coalesce onto the
one refresh genuinely in flight; a request that arrives after that refresh has settled MUST take a
fresh snapshot rather than be handed the settled one.

Mutation suppression MUST be evaluated at the moment a re-snapshot would actually start, not only
when a signal arrives and when the quiet window opens. A quiet window that opened before a mutation
began MUST NOT fire a re-snapshot while that mutation is in flight; it MUST be folded into the single
re-snapshot owed at the mutation's terminal outcome.

An acquisition already in flight MUST NOT be used to answer a change signal that arrived after that
acquisition started: such a signal MUST invalidate the in-flight result for freshness purposes and
cause a further re-snapshot once the quiet window elapses, so the inventory converges on state
observed at or after the newest signal.

Resetting the inventory to a detection-driven state — for example clearing it because detection
reported brew absent — while an acquisition is in flight MUST NOT strand that acquisition. The
inventory MUST remain able to run and publish a later refresh, and MUST NOT stay stuck in the
cleared state after a subsequent successful refresh.

#### Scenario: An external install is reflected without user action

- GIVEN a running inventory and a change source under test control
- WHEN the underlying snapshot gains a package and one change signal is emitted
- THEN after the quiet window the inventory lists the new package
- AND no user action was required

#### Scenario: A burst of signals causes exactly one re-snapshot

- GIVEN a running inventory
- WHEN twenty change signals are emitted within the quiet window
- THEN exactly one additional brew invocation is recorded

#### Scenario: Signals during a mutation are suppressed and settled once

- GIVEN a Cellar-initiated mutation in flight
- WHEN change signals are emitted continuously until that mutation reaches a terminal outcome
- THEN no re-snapshot runs while the mutation is in flight
- AND exactly one re-snapshot runs at the terminal outcome

#### Scenario: A refresh requested after the one in flight settles is fresh

- GIVEN a refresh that has already completed against a snapshot payload `P1`
- WHEN a refresh is requested afterwards and the payload is now `P2`
- THEN a second invocation is performed
- AND the inventory reflects `P2`

#### Scenario: A window opened before a mutation began does not fire during it

- GIVEN a change signal that opened the quiet window
- WHEN a Cellar-initiated mutation begins before that window elapses, and the window then elapses
  while the mutation is still in flight
- THEN no re-snapshot runs while the mutation is in flight
- AND exactly one re-snapshot runs at the mutation's terminal outcome

#### Scenario: A signal during an acquisition is not answered by that acquisition

- GIVEN an acquisition in flight against snapshot payload `P1`
- WHEN a change signal is emitted after that acquisition started and the underlying payload is now
  `P2`
- THEN a further invocation is performed after the quiet window
- AND the inventory reflects `P2`, not `P1`

#### Scenario: Resetting during an acquisition does not strand the inventory

- GIVEN an acquisition in flight that has not yet settled
- WHEN the inventory is reset to the brew-absent state before it settles, and detection later
  reports a valid installation and a refresh is requested
- THEN that refresh performs an invocation and publishes its snapshot
- AND the inventory does not remain empty

### Requirement: Refresh loops are owned for the app's lifetime

Background refresh loops MUST be owned for the lifetime of the application rather than by any single
window. Closing the window that started the app MUST NOT stop them. Opening an additional window
MUST NOT start a second loop, and reopening a window after all were closed MUST NOT start another
one; at most one loop of each kind runs per launch.

#### Scenario: Closing the starting window does not stop the loops

- GIVEN the app has launched and its refresh loops are running
- WHEN the window that started the app is closed
- THEN the loops are still running
- AND a subsequent refresh still updates the inventory

#### Scenario: A second window does not start a second loop

- GIVEN the app has launched with its refresh loops running
- WHEN a second window is opened, then all windows are closed and a new one is opened
- THEN exactly one loop of each kind is running throughout

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

## Provenance

- Established by change `m2-installed-inventory` (archived `2026-08-02`), ADDED-only delta — **11
  requirements / 34 scenarios**, copied verbatim from
  `openspec/changes/archive/2026-08-02-m2-installed-inventory/specs/installed-inventory/spec.md`.
  This is the first main spec for the capability; nothing was modified, removed or renamed. This
  file adds only the header, the `## Requirements` wrapper, and this provenance section.
- Two binding inputs were settled *before* the delta was written and are stated in it as facts, not
  open questions:
  - **Product decisions** (user-confirmed 2026-08-02, Engram `#7079`): the default installed view is
    on-request only; auto-updating casks never badge as outdated; browse installed-state filters
    ship in this change, composed through this capability.
  - **Live probe** (brew 6.0.14, Engram `#7081`): the `info --installed` snapshot already applies
    brew's auto-updates exclusion to a cask's `outdated` flag, and the same record carries both the
    catalog `version` and the `installed` string, so a "newer version exists" signal for a
    self-updating cask is derivable without a second invocation. This is why "A self-updating cask's
    newer version is derived from the same probe" forbids a second brew invocation rather than
    reserving `brew outdated --greedy` as a fallback.
- **`package-search` is deliberately untouched by this capability.** Its requirement "Filters
  answerable from the catalog alone" — including "No filter MUST depend on installed, not-installed,
  or outdated state" — remains correct and byte-identical; composition happens above the index. The
  invariant is re-asserted here as the scenario "The catalog filter set still declares no installed
  predicate", so a future change cannot quietly push installed state into the search index without
  failing a scenario in *this* capability too.
- **Implementation note for "On-request and dependency-only are derived, and the default view is
  on-request"** (recorded at archive, from the docs review of
  `openspec/changes/m2-mutations-installed/explore.md`): the requirement's premise "the payload
  carries no `installed_as_dependency` field" is the *derivation contract this capability
  implements*, and the derivation is a correct fallback either way. The blanket claim that the field
  does not exist in `brew info --json=v2` is over-generalised — the change's own fixture models the
  field. Read the requirement as "on-request state MUST be derived from the on-request marker", not
  as a schema assertion about Homebrew's JSON.
- **Implementation note for "External changes invalidate the inventory, debounced and coalesced"**
  (native review lineage `review-bbe42e6b3e7d13e7`, WARNINGs, non-blocking): as delivered, the
  mutation gate is checked when a signal arrives and again when the quiet window opens, but not
  re-checked after an already-open window elapses; and `clear(to:)` while a refresh is in flight can
  strand the in-flight acquisition. Both are latent until `m2-mutations-installed` (M2-2) drives the
  `isMutating` flag with real mutations; the requirement text is unchanged and all four scenarios are
  COMPLIANT. Tracked in the M2-1 archive report's follow-up register, not as a spec gap.
  **Closed by `m2-mutations-activity`** — see the amendment below, which specifies the behaviour the
  note described as a gap.
- **Amended by change `m2-mutations-activity` (archived `2026-08-02`, PRD milestone **M2**, slice
  M2-2)**: **2 MODIFIED** requirements replaced as whole blocks, adding **5 scenarios**.
  11 requirements / 34 scenarios → **11 requirements / 39 scenarios**. Nothing was added, removed or
  renamed; the other nine requirements are byte-identical. Both amendments close behavioural gaps the
  M2-1 archive routed to M2-2 — they were latent because nothing drove the mutation gate with a real
  mutation, and M2-2 is the change that does.
  - **"Installed-state filters are composed, never pushed into the search index"** gained the rule
    that catalog-only controls (kind, deprecated, disabled) under the installed and outdated browse
    modes MUST either apply or render disabled, plus 2 scenarios. Previously the requirement governed
    only the three installed-state filters and said nothing about the catalog-only controls shown
    beside them, so those controls rendered **enabled but inert** under installed and outdated modes
    (M2-1 follow-up 1). Delivered as `InstalledBrowse.rows(filters:)` — the parameter is *required*,
    not defaulted, so no call site can silently ignore the controls — with `kinds` read from
    `InstalledPackage.kind` (the inventory is authoritative) and deprecated/disabled applied as
    catalog predicates through the existing catalog-lookup decoration, where **no catalog record ⇒
    not excluded**, preserving this capability's own "an unmatched installed package is still listed"
    principle.
  - **"External changes invalidate the inventory, debounced and coalesced"** gained three paragraphs
    and 3 scenarios covering (a) suppression re-checked at the moment a re-snapshot would start, so a
    window opened before a mutation began cannot fire during it (M2-1 follow-up 3); (b)
    invalidation-after-start, so an in-flight acquisition never answers a signal that arrived after it
    started and the inventory can no longer settle on pre-change state (M2-1 follow-up 2); (c) reset
    during acquisition not stranding the slot, so the inventory cannot stay stuck empty after a later
    successful refresh (M2-1 follow-up 4). Delivered as a stored, cancellable debounce task with a
    post-sleep gate re-check, a monotonic `invalidationCount` with a per-acquisition mark that a
    joiner must match, and a `clear(to:)` that cancels and vacates the in-flight slot **before**
    bumping the publication ordinal.
- **Verification note on the mutation gate's depth** (`m2-mutations-activity` verify ruling 1,
  2026-08-02): "exactly one re-snapshot at that mutation's terminal outcome" is satisfied by a
  **depth-counted** gate — `begin()` per submission, `end()` per terminal, floor zero, always
  yielding. A selected upgrade fans out into N independent operations, so N terminals owe N
  re-snapshots while `isMutating` must still cover the whole batch. One-begin-per-batch would drop
  the depth to zero after the first terminal and reopen suppression mid-batch, violating this
  requirement's suppression clause.
- **Verification note on post-terminal signals** (`m2-mutations-activity` verify ruling 2,
  2026-08-02): a change signal produced by a mutation's own writes but arriving **after** its
  terminal outcome falls outside the suppression clause, which is scoped to "while a mutation is in
  flight". It is then correctly governed by the ordinary external-change clauses — not parsed,
  debounced into exactly one refresh. Conforming, not a violation; a short post-terminal grace window
  would absorb the redundant probe and is carried as a follow-up, not a spec gap.
- **`package-mutation` owns the mutation side of this contract.** Its requirement "Every terminal
  outcome forces one re-snapshot, and cancel is reported honestly" is the counterpart to the
  suppression clause here; the two are written to be read together and must not drift.
- **Verification note for "Installed-state filters are composed, never pushed into the search
  index" and "Refresh loops are owned for the app's lifetime"** (verify WARNING 2, 2026-08-02): the
  rule side (`InstalledBrowse.isFilterEnabled`, `LoopOwner`) is unit-tested in the package; the app
  target's bindings that consume it (`CatalogFilterBar`'s `.disabled(...)`, `cellarApp`'s
  `loops.start(...)` calls) are proven by `xcodebuild test` plus manual screenshot rather than by a
  unit test. Design-sanctioned Phase 9 strategy, recorded as a real coverage boundary.
- **Amended by change `m2-local-metadata-history` (archived `2026-08-03`, PRD milestone **M2**, slice
  M2-3 — the last M2 slice)**: **1 MODIFIED** requirement replaced as a whole block (adding
  **3 scenarios**) and **3 ADDED** requirements (**12 scenarios**). 11 requirements / 39 scenarios →
  **14 requirements / 54 scenarios**. Nothing was removed or renamed; the other ten requirements are
  byte-identical, and the MODIFIED replacement is a strict superset of the text it replaced.
  - **"Installed-state filters are composed, never pushed into the search index"** gained the
    favorites filter, composed on exactly the same terms as the installed-state filters, plus the rule
    that locally stored **note text MUST NOT enter any search index**. 3 scenarios added, and the
    existing "The catalog filter set still declares no installed predicate" scenario now also excludes
    a favorite predicate. Favorites are a filter-bar entry, **not** a sidebar section (product
    decision, user-confirmed 2026-08-02, Engram `#7111`). The no-membership-predicate claim is
    asserted by `Mirror` reflection over the real `SearchFilters` type, so a future change cannot
    quietly add one.
  - **"Snoozed packages leave the outdated section and its count"** is ADDED rather than folded into
    "Auto-updating casks never count as outdated", because it does not alter the existing
    self-updating-cask derivation — it is a projection composed above it. It consumes
    `local-package-metadata`'s equality rule and MUST NOT introduce a version comparator; the list and
    the browse filter are required to agree so they cannot drift.
  - **"Multi-select is explicit, ordered, and offered only for bulk-eligible verbs"** makes selection
    part of the installed list's observable model. Order is load-bearing — it determines submission
    order — so the app keeps the native `List(selection:)` `Set<PackageID>` binding for range
    selection, VoiceOver and Select All, and maintains an ordered `[PackageID]` **beside** it; the
    ordered array is the only thing the bulk surface and the confirmation sheet read. Bulk affordances
    are restricted to upgrade and uninstall; PRD §3.2 also lists pin and snooze as bulk verbs, and
    those were **deliberately narrowed out** (settled 2026-08-02) — the restriction is proven
    exhaustively over `BulkSelection.Action.allCases`.
  - **"A bulk action's label counts exactly the set it submits"** closed M2-2 follow-up 1: the label
    counted the *dependency-filtered* entries while `submitUpgradesForOutdated` filtered the **whole
    inventory**, so the button could promise fewer upgrades than it submitted
    (`InstalledListView.swift:83`). Closed by deriving both from one projection — the count is
    computed from `upgradableIDs`, the exact set the action submits — and the old divergent helper was
    deleted outright.
- **Known follow-up (`m2-local-metadata-history` native review lineage `review-e07590a04c4aff38`,
  SUGGESTION, non-blocking)**: `InstalledListView.reconcileOrder(with:)` appends newly selected ids in
  **flat inventory order**, while a nearby comment claims the three-section displayed order. Selection
  order is still deterministic and reproducible — never `Set` iteration order — so no scenario is
  violated; the divergence is between the code and its own comment for a multi-add gesture. Tracked as
  follow-up S2 in the M2-3 archive report.
