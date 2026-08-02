# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (11 requirements / 34 scenarios).

Delta summary: **2 MODIFIED requirements / 14 scenarios**, both reproduced in full so the archive
step loses nothing. Nothing is ADDED, REMOVED or RENAMED.

Both amendments close behavioural gaps the M2-1 archive routed here, recorded in its follow-up
register and in the main spec's provenance (native review lineage `review-bbe42e6b3e7d13e7`,
WARNINGs, non-blocking at the time). They were latent because nothing drove the mutation gate with a
real mutation; M2-2 is the change that does, so they become live defects here and are specified now:

1. **Mutation suppression is not re-checked after an open quiet window** — the gate is consulted when
   a signal arrives and when the window opens, but a window that opened *before* a mutation began can
   still fire a re-snapshot while that mutation is in flight.
2. **A signal arriving during an acquisition is answered by that pre-signal acquisition** — the
   inventory can settle on state observed strictly before the change it was told about.
3. **Resetting the inventory while an acquisition is in flight strands the slot** — the inventory can
   stay stuck empty even after a later successful refresh.
4. **Catalog-only filter controls are enabled but inert under installed and outdated browse modes** —
   the kind, deprecated and disabled controls render enabled and change nothing.

Fixes 1–3 amend "External changes invalidate the inventory, debounced and coalesced"; fix 4 amends
"Installed-state filters are composed, never pushed into the search index". Both amendments extend
the requirement that already owns the behaviour rather than competing with a new one.

`package-search` remains untouched: fix 4 is a composition and control-state rule above the index,
and the requirement's existing scenario "The catalog filter set still declares no installed
predicate" is carried over unchanged.

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
(Previously: the requirement governed only the three installed-state filters and said nothing about
the catalog-only controls shown alongside them, so under installed and outdated modes the kind,
deprecated and disabled controls rendered enabled while having no effect on the results.)

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
- THEN it contains no installed, not-installed or outdated predicate

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
(Previously: suppression was checked only on signal arrival and at window open, so an already-open
window could re-snapshot during a mutation; an in-flight acquisition could answer a signal that
arrived after it started, settling on pre-change state; and resetting during an acquisition could
strand the slot, leaving the inventory stuck empty after a later successful refresh.)

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
