# Delta for installation-history

Existing capability — `openspec/specs/installation-history/spec.md` (7 requirements / 21 scenarios).

Delta summary: **1 MODIFIED requirement — 6 scenarios (4 carried forward unchanged, 2 added)**. The
MODIFIED requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED,
REMOVED or RENAMED.

The requirement rules what a *confirmed* and a *declined* clear must do, but says nothing about one
that **fails** — today indistinguishable from a healthy empty history, because the recorded failure
is overwritten by the projection reload that follows and no reason is ever reported. Settled: the
reason is surfaced **inline** through the projection's existing availability and error surface — no
blocking alert, no retry affordance — and the clear stays all-or-nothing.

## MODIFIED Requirements

### Requirement: Clear history is a single confirmed all-or-nothing action

Clearing the history MUST require an explicit confirmation before anything is deleted. A confirmed
clear MUST remove every entry and MUST remove nothing else — locally stored favorites, notes and
snoozes MUST be untouched. Declining MUST delete nothing. The capability MUST NOT offer selective or
per-entry deletion.

A confirmed clear that fails MUST remain all-or-nothing and MUST be observable. Every entry MUST
still be present and readable afterwards, and the history MUST NOT be presented as emptied or as
healthy. The failure MUST be reported inline with a reason, through the projection's own availability
and error surface, and that reason MUST survive the projection reload that follows the attempt rather
than being overwritten by it. A failed clear MUST NOT raise a blocking alert and MUST NOT offer a
retry affordance.
(Previously: the requirement covered only a confirmed clear and a declined clear; a clear that failed
was left undefined and could be presented as an emptied, healthy history with no reason reported.)

#### Scenario: A confirmed clear empties the history

- GIVEN a history of several entries
- WHEN clear is requested and confirmed
- THEN the history is empty

#### Scenario: Declining deletes nothing

- GIVEN a history of several entries and a pending clear confirmation
- WHEN the confirmation is declined
- THEN every entry is still present

#### Scenario: A failed clear leaves every entry present and reports why

- GIVEN a history of three entries and a store whose deletion fails
- WHEN clear is requested and confirmed
- THEN all three entries are still present and readable, with their original fields
- AND the failure is reported with a reason rather than as an empty history

#### Scenario: A failed clear's reason survives the reload that follows it

- GIVEN a confirmed clear that has just failed
- WHEN the projection reloads after the attempt and its availability and error surface is read
- THEN the clear failure and its reason are still reported, not a healthy or available-and-empty
  history
- AND no blocking alert and no retry control is presented for it

#### Scenario: Clearing history leaves local metadata intact

- GIVEN stored favorites, notes and snoozes alongside a non-empty history
- WHEN clear is requested and confirmed
- THEN the history is empty
- AND every favorite, note and snooze is still readable with its original value

#### Scenario: No per-entry delete affordance exists

- WHEN the controls the history projection exposes for a single entry are enumerated
- THEN no delete or remove control is present for that entry
