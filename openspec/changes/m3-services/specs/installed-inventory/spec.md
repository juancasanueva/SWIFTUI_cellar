# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (14 requirements / 55 scenarios).

Delta summary: **1 MODIFIED requirement — 9 scenarios (7 carried forward, 2 added)**. The MODIFIED
requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED, REMOVED or
RENAMED. 14 requirements / 55 scenarios → **14 requirements / 57 scenarios**.

Only **II10 "External changes invalidate the inventory, debounced and coalesced"** changes, and only
where it drives the mutation gate. `package-mutation` PM6 becomes a typed invalidation scope declared
by the command in this same slice; II10 is the other half of that contract and MUST NOT drift from
it. Everything else about II10 — the not-parsed rule, the debounce, the coalescing, the
re-check-at-start rule, invalidation-after-start, and reset-during-acquisition — is carried forward
byte-identical.

**II13 "Multi-select is explicit, ordered, and offered only for bulk-eligible verbs" is untouched,
and that is load-bearing.** Its scenario "Only upgrade and uninstall are offered for a selection" is
proven exhaustively over the installed list's bulk-action vocabulary. This slice ships **no** bulk
service affordance; a future services multi-select MUST be its own type over its own entity and MUST
NOT be added as a case to the installed list's bulk-action vocabulary. `service-management` states
the same rule from its side so the two cannot drift.

**Deliberately NOT specified here: the post-terminal FSEvents grace window.** The proposal lists it
as absorbed work (M2-2 follow-up 6). Writing it into this requirement would collide with the
carried-forward clause "An acquisition already in flight MUST NOT be used to answer a change signal
that arrived after that acquisition started" — a grace window that folds a post-terminal signal into
an already-running re-snapshot would weaken exactly that freshness guarantee. The grace window
remains an implementation-level coalescing that MUST be built **inside** the invalidation-after-start
rule, not a licence to relax it. Flagged for `sdd-design`.

## MODIFIED Requirements

### Requirement: External changes invalidate the inventory, debounced and coalesced

An external change to the installed packages MUST be reflected without user action. The change
signal MUST be treated purely as an invalidation trigger: its contents MUST NOT be parsed to derive
inventory state — a re-snapshot is always taken instead. Bursts of signals MUST be coalesced on an
injected clock so that a burst within the quiet window causes exactly one re-snapshot. While a
Cellar-initiated mutation **that invalidates the installed set** is in flight, signals MUST be
suppressed, and exactly one re-snapshot MUST be taken at that mutation's terminal outcome.
Overlapping refresh requests MUST coalesce onto the one refresh genuinely in flight; a request that
arrives after that refresh has settled MUST take a fresh snapshot rather than be handed the settled
one.

Suppression and the owed re-snapshot MUST be scoped to commands that declare they invalidate the
installed set, as `package-mutation` requires each command to declare. A Cellar-initiated operation
that does not declare the installed set MUST NOT suppress external change signals while it runs, and
MUST NOT force an inventory re-snapshot at its terminal outcome; external changes observed while such
an operation runs MUST be handled by the ordinary debounce and coalescing rules above.

Mutation suppression MUST be evaluated at the moment a re-snapshot would actually start, not only
when a signal arrives and when the quiet window opens. A quiet window that opened before an
inventory-invalidating mutation began MUST NOT fire a re-snapshot while that mutation is in flight;
it MUST be folded into the single re-snapshot owed at the mutation's terminal outcome.

An acquisition already in flight MUST NOT be used to answer a change signal that arrived after that
acquisition started: such a signal MUST invalidate the in-flight result for freshness purposes and
cause a further re-snapshot once the quiet window elapses, so the inventory converges on state
observed at or after the newest signal.

Resetting the inventory to a detection-driven state — for example clearing it because detection
reported brew absent — while an acquisition is in flight MUST NOT strand that acquisition. The
inventory MUST remain able to run and publish a later refresh, and MUST NOT stay stuck in the
cleared state after a subsequent successful refresh.
(Previously: suppression and the owed re-snapshot applied to **every** Cellar-initiated mutation
unconditionally, so a mutation that cannot change the installed set both suppressed genuine external
signals and paid a full re-snapshot it could learn nothing from.)

#### Scenario: An external install is reflected without user action

- GIVEN a running inventory and a change source under test control
- WHEN the underlying snapshot gains a package and one change signal is emitted
- THEN after the quiet window the inventory lists the new package
- AND no user action was required

#### Scenario: A burst of signals causes exactly one re-snapshot

- GIVEN a running inventory
- WHEN twenty change signals are emitted within the quiet window
- THEN exactly one additional brew invocation is recorded

#### Scenario: Signals during an inventory-invalidating mutation are suppressed and settled once

- GIVEN a Cellar-initiated mutation declaring the installed set, in flight
- WHEN change signals are emitted continuously until that mutation reaches a terminal outcome
- THEN no re-snapshot runs while the mutation is in flight
- AND exactly one re-snapshot runs at the terminal outcome

#### Scenario: A refresh requested after the one in flight settles is fresh

- GIVEN a refresh that has already completed against a snapshot payload `P1`
- WHEN a refresh is requested afterwards and the payload is now `P2`
- THEN a second invocation is performed
- AND the inventory reflects `P2`

#### Scenario: A window opened before an inventory-invalidating mutation began does not fire during it

- GIVEN a change signal that opened the quiet window
- WHEN a Cellar-initiated mutation declaring the installed set begins before that window elapses, and
  the window then elapses while the mutation is still in flight
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

#### Scenario: An operation that does not invalidate the installed set forces no re-snapshot

- GIVEN a Cellar-initiated operation whose declared invalidation scope excludes the installed set
- WHEN it reaches a successful terminal outcome, and separately a failed and a cancelled one
- THEN no inventory re-snapshot is forced in any of the three cases
- AND no `brew info --installed --json=v2` invocation is recorded for them

#### Scenario: External signals are not suppressed by a non-invalidating operation

- GIVEN a Cellar-initiated operation whose declared invalidation scope excludes the installed set, in
  flight, and a change source under test control
- WHEN the underlying snapshot gains a package and one change signal is emitted while that operation
  is still running
- THEN after the quiet window the inventory lists the new package, without waiting for that operation
  to finish
