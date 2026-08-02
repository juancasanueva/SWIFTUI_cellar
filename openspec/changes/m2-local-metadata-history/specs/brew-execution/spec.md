# Delta for brew-execution

Existing capability — `openspec/specs/brew-execution/spec.md` (6 requirements / 15 scenarios).

Delta summary: **1 MODIFIED requirement / 10 scenarios**, reproduced in full so the archive step
loses nothing. Nothing is ADDED, REMOVED or RENAMED.

This closes M2-2 follow-up 4, which the archive routed here and which is a **hard prerequisite** for
`installation-history`: the runner's operation records are never evicted, so they accumulate for the
whole process lifetime, and `queuePhase` is republished without an equality guard, producing
observable churn on every yield. Durable retention of what Cellar did belongs to
`installation-history`; the runner keeps only what execution still needs.

The retirement specified here is confined to the execution layer's own records. The session-long
queue projection is owned by `operation-activity`, whose amended requirement in this same change
states that a retired execution record does not remove its queue item. The two clauses are written to
be read together and must not drift.

## MODIFIED Requirements

### Requirement: Serialized mutations with concurrent reads

At most one mutating operation MAY be in flight. Queued mutations MUST run FIFO. Read-only queries
MUST NOT be blocked by an in-flight mutation. A mutation cancelled while queued MUST NOT spawn a
process.

Every submitted operation MUST be assigned a stable identity at submission time. That identity MUST
NOT change for the lifetime of the operation, MUST distinguish two otherwise identical submissions
of the same command, and MUST carry the exact argv the operation was submitted with. The runner MUST
expose a read-only enumeration of its operations — each with its identity, its argv, and its state
(pending, running, or terminal) — with pending mutations enumerated in the FIFO order they will run.
Enumerating MUST NOT start, delay, reorder, cancel or otherwise perturb any operation, and MUST NOT
block on one in flight.

Retention of those records MUST be bounded: they MUST NOT accumulate for the lifetime of the process.
A record MUST be retired only once its operation is terminal **and** its result has been drained, so
the operation's exit MUST remain answerable for any operation still being awaited, and retiring a
record MUST never affect a pending or running operation. A retired operation MUST NOT be reported as
pending or running by the enumeration, and MUST NOT be re-spawned, re-queued or resurrected in any
form.

An operation's observable phase MUST NOT be republished when its value has not changed, so observers
see one change per real transition rather than one per yield.
(Previously: records were retained for the whole process lifetime with no retirement rule at all, and
the queue phase was published on every yield without an equality guard.)

#### Scenario: Two mutations never overlap

- GIVEN mutation A is in flight
- WHEN mutation B is submitted
- THEN B does not start until A reaches a terminal outcome, and start order is A then B

#### Scenario: Reads proceed during a mutation

- GIVEN a mutation is in flight
- WHEN a read-only query is submitted
- THEN it starts and completes without waiting for the mutation

#### Scenario: Cancelling a queued mutation spawns nothing

- GIVEN mutation B is queued behind in-flight mutation A
- WHEN B is cancelled before A finishes
- THEN no process is spawned for B and B reports cancelled

#### Scenario: Queued mutations are enumerable before they run

- GIVEN mutation A is in flight and mutations B then C are submitted
- WHEN the runner's operations are enumerated
- THEN A is reported running, and B and C are reported pending in the order B then C
- AND each entry carries the argv its operation was submitted with

#### Scenario: An operation's identity is stable and distinguishes identical submissions

- GIVEN the same command submitted twice
- WHEN both operations are enumerated while pending, while running, and once terminal
- THEN each operation keeps one identity across all three states
- AND the two identities are different from each other

#### Scenario: Enumerating does not perturb scheduling

- GIVEN mutation A in flight with mutations B and C queued behind it
- WHEN the operations are enumerated repeatedly while A runs
- THEN no additional process is spawned
- AND the start order after A completes is still B then C

#### Scenario: Records stop accumulating

- GIVEN a runner over which many operations have each reached a terminal outcome and had their
  results drained
- WHEN the number of records the runner holds is read
- THEN it is bounded rather than growing with the number of operations run

#### Scenario: A terminal operation not yet drained is still answerable

- GIVEN a terminal operation whose result has not yet been awaited
- WHEN its exit is requested
- THEN it is answered with that operation's terminal outcome

#### Scenario: Retirement never touches a pending or running operation

- GIVEN a runner with one running operation, one pending operation, and several drained terminal
  operations
- WHEN retirement occurs
- THEN the running and pending operations are still enumerated in their original order
- AND no process was spawned, cancelled or restarted by the retirement

#### Scenario: An unchanged phase is not republished

- GIVEN an observer of the runner's queue phase
- WHEN the same phase value is produced repeatedly without a real transition
- THEN the observer sees one change for the transition into that phase and none for the repeats
