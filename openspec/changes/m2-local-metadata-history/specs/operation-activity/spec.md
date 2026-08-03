# Delta for operation-activity

Existing capability — `openspec/specs/operation-activity/spec.md` (5 requirements / 15 scenarios).

Delta summary: **2 MODIFIED requirements / 1 ADDED requirement — 14 scenarios**. Both MODIFIED
requirements are reproduced in full so the archive step loses nothing. Nothing is REMOVED or RENAMED.

What changes here:

1. **Cancel stays effective when the executing backend is detached** — M2-2 follow-up 2: a cancel
   issued while the queue was detached from its runner settled the item as cancelled without
   signalling the process, and paid the mutation gate's `end()` early. The process kept running while
   the item became uncancellable. Bulk multi-select multiplies the exposure, so it is closed here.
2. **The session enumeration no longer depends on execution-layer record retention** — this slice
   makes `brew-execution` retire terminal runner records, so this capability must state that its own
   session-long enumeration survives that retirement. Without this clause the two capabilities would
   silently contradict each other.
3. **Every terminal outcome records exactly one history entry** — the bridge between this capability
   and `installation-history`, which owns what is written and how long it is kept.

## MODIFIED Requirements

### Requirement: The operation queue is enumerable, ordered, and carries each operation's argv

Every submitted operation MUST be projected as an enumerable item carrying a stable identity, the
package identity it acts on when it has one, its exact argv, its state — pending, running, or
terminal — and, once terminal, its outcome. The identity MUST be assigned at submission and MUST NOT
change as the operation moves between states, so an observer can follow one operation across its
whole lifetime. Pending operations MUST be enumerated in the order brew will actually run them.
A terminal operation MUST remain enumerable for the rest of the session. Enumerating MUST be
read-only: it MUST NOT start, delay, reorder or otherwise perturb any operation.

This session-long enumeration MUST NOT depend on the execution layer retaining its own record of an
operation. When `brew-execution` retires a terminal, fully drained record, the operation MUST still
be enumerated here with its identity, argv and terminal outcome for the rest of the session.
(Previously: the requirement said a terminal operation remains enumerable for the session but did not
say where that guarantee is sourced from; the execution layer never retired a record, so the
distinction had no consequence.)

#### Scenario: Pending operations are visible before they run, in run order

- GIVEN mutation A is running and mutations B and C are submitted in that order
- WHEN the queue projection is enumerated
- THEN A is reported running, and B and C are reported pending in the order B then C

#### Scenario: An operation's identity is stable across its states

- GIVEN a submitted mutation observed while pending, while running, and once terminal
- WHEN its identity is read at each point
- THEN the identity is the same value every time

#### Scenario: Each enumerated operation carries the exact argv

- GIVEN an install submitted for the cask `iterm2`
- WHEN it is enumerated while pending and again once terminal
- THEN both projections report the argv `install --cask iterm2`

#### Scenario: Terminal operations remain enumerable for the session

- GIVEN a mutation that has reached a terminal outcome
- WHEN the queue projection is enumerated afterwards
- THEN the operation is still listed with its terminal outcome
- AND enumerating it did not spawn or restart anything

#### Scenario: A retired execution record does not remove the queue item

- GIVEN a terminal, fully drained operation whose execution-layer record has been retired
- WHEN the queue projection is enumerated
- THEN the operation is still listed with its identity, its argv and its terminal outcome

### Requirement: Cancel is offered from pending and running, and is the only queue control

Cancel MUST be offered for pending operations and for the running one. Cancelling a pending
operation MUST resolve it as cancelled without spawning any process — the guarantee owned by
`brew-execution`, which this capability exposes rather than re-implements. Cancelling the running
operation MUST use the existing cancellation escalation and MUST be reported as cancelled, never as
a failure, and the next pending operation MUST then start. This capability MUST NOT offer reordering
or removal of queued operations, and the queue order MUST NOT be mutable from any surface it
exposes.

Cancel MUST remain effective for an operation that is actually running, regardless of whether the
queue is currently attached to the executing backend. The capability MUST NOT report an operation as
cancelled while its process is still running: a cancel MUST signal the running process, and the item
MUST settle as cancelled only at the real terminal outcome. The mutation gate MUST NOT be released,
and the forced re-snapshot MUST NOT be taken, before that real terminal outcome — so a cancel issued
while detached can never leave a running, uncancellable operation behind an already-reopened gate.
(Previously: cancelling while the queue was detached from its runner settled the item as cancelled
without signalling the process and paid the gate's release early, after which the still-running
operation could not be cancelled again.)

#### Scenario: Cancelling a pending operation spawns nothing

- GIVEN mutation B pending behind running mutation A
- WHEN B is cancelled from the queue projection before A finishes
- THEN no process is spawned for B
- AND B is enumerated as terminal with the cancelled outcome

#### Scenario: Cancelling the running operation lets the queue proceed

- GIVEN mutation A running with mutation B pending behind it
- WHEN A is cancelled
- THEN A is reported cancelled rather than failed
- AND B starts afterwards

#### Scenario: No reorder or remove affordance exists

- WHEN the controls the queue projection exposes for a pending operation are enumerated
- THEN cancel is present
- AND no reorder, move or remove control is present

#### Scenario: Cancelling while detached still stops the process

- GIVEN a running mutation whose queue has been detached from its executing backend
- WHEN the operation is cancelled
- THEN the running process is signalled through the ordinary cancellation escalation
- AND the operation is reported cancelled only once that process has stopped

#### Scenario: A detached cancel does not release the gate early

- GIVEN a running mutation, detached as above, with another mutation pending behind it
- WHEN the operation is cancelled and its process has not yet stopped
- THEN the pending mutation has not started
- AND no inventory re-snapshot has been forced
- AND both happen exactly once when the real terminal outcome arrives

## ADDED Requirements

### Requirement: Every terminal outcome records exactly one history entry

When an operation this capability projects reaches a terminal outcome, exactly one history entry MUST
be submitted for it — never zero and never two — carrying that operation's package identity when it
has one, its verb, its exact argv and its outcome. Success, failure and cancellation MUST each be
recorded. Nothing MUST be submitted while the operation is pending or running. Recording MUST be a
side effect: if it is unavailable or fails, the operation's reported outcome, its log, and the forced
re-snapshot owed at that outcome MUST be unchanged. What the entry stores and how long it is kept are
owned by `installation-history`.

#### Scenario: A successful operation records once

- GIVEN a submitted install for the cask `iterm2` that exits with status 0
- WHEN it reaches its terminal outcome
- THEN exactly one history entry was submitted for it, carrying the argv `install --cask iterm2` and
  a successful outcome

#### Scenario: A cancelled operation records its cancellation

- GIVEN a running mutation
- WHEN it is cancelled and reaches the cancelled outcome
- THEN exactly one history entry was submitted for it, carrying the cancelled outcome

#### Scenario: Nothing is recorded before the terminal outcome

- GIVEN a mutation that is pending, and separately one that is running
- WHEN the recorded entries are enumerated
- THEN no entry exists for either operation

#### Scenario: A failing recorder does not change what the queue reports

- GIVEN a history recorder that fails on every write
- WHEN a mutation reaches its terminal outcome
- THEN the operation's reported outcome and log are identical to the same run with a working recorder
- AND exactly one inventory re-snapshot was forced
