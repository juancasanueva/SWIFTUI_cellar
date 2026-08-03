# Delta for operation-activity

Existing capability — `openspec/specs/operation-activity/spec.md` (7 requirements / 22 scenarios).

Delta summary: **1 MODIFIED requirement — 5 scenarios (4 carried forward unchanged, 1 added)**. The
MODIFIED requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED,
REMOVED or RENAMED.

The exactly-one-entry rule is stated for operations reaching a terminal outcome, but one that never
spawns a process — no runner configured, or a launch that fails before a process exists — settles
beside that rule and writes nothing. Settled: yes, one entry, no carve-out, including for an identity
the runner cannot answer. What the entry stores and how long it is kept remain owned by
`installation-history`.

## MODIFIED Requirements

### Requirement: Every terminal outcome records exactly one history entry

When an operation this capability projects reaches a terminal outcome, exactly one history entry MUST
be submitted for it — never zero and never two — carrying that operation's package identity when it
has one, its verb, its exact argv and its outcome. Success, failure and cancellation MUST each be
recorded. Nothing MUST be submitted while the operation is pending or running. Recording MUST be a
side effect: if it is unavailable or fails, the operation's reported outcome, its log, and the forced
re-snapshot owed at that outcome MUST be unchanged. What the entry stores and how long it is kept are
owned by `installation-history`.

An operation that reaches a terminal outcome **without ever spawning a process** MUST be treated as a
terminal outcome like any other: no runner configured to execute it, a launch that fails before a
process exists, and an identity the execution layer cannot answer MUST each record exactly one entry
carrying that operation's argv and its failure outcome. This rule MUST hold with no carve-out — a
settled outcome that is reported to the queue but writes no entry is forbidden, whatever path settled
it.
(Previously: the requirement covered every terminal outcome but was satisfied only on paths that had
spawned a process; an operation settled without ever spawning could reach its terminal outcome and
record zero entries.)

#### Scenario: A successful operation records once

- GIVEN a submitted install for the cask `iterm2` that exits with status 0
- WHEN it reaches its terminal outcome
- THEN exactly one history entry was submitted for it, carrying the argv `install --cask iterm2` and
  a successful outcome

#### Scenario: A cancelled operation records its cancellation

- GIVEN a running mutation
- WHEN it is cancelled and reaches the cancelled outcome
- THEN exactly one history entry was submitted for it, carrying the cancelled outcome

#### Scenario: An operation that never spawns still records once

- GIVEN a queue with no runner configured to execute submissions
- WHEN a mutation is submitted and settles at its terminal outcome without a process ever existing
- THEN it is reported as a failed terminal outcome, not as pending, running or successful
- AND exactly one history entry was submitted for it, carrying its argv and that failure outcome

#### Scenario: Nothing is recorded before the terminal outcome

- GIVEN a mutation that is pending, and separately one that is running
- WHEN the recorded entries are enumerated
- THEN no entry exists for either operation

#### Scenario: A failing recorder does not change what the queue reports

- GIVEN a history recorder that fails on every write
- WHEN a mutation reaches its terminal outcome
- THEN the operation's reported outcome and log are identical to the same run with a working recorder
- AND exactly one inventory re-snapshot was forced
