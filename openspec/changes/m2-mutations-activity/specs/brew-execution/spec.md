# Delta for brew-execution

Existing capability — `openspec/specs/brew-execution/spec.md` (6 requirements / 12 scenarios).

Delta summary: **1 MODIFIED requirement / 6 scenarios**, reproduced in full so the archive step loses
nothing. Nothing is ADDED, REMOVED or RENAMED.

The change is additive to the existing queue: the FIFO gate, the read/mutation split and the
cancellation policy are all unchanged. What is added is *observability* — the queue stops being a
private detail and becomes an enumerable, read-only projection with a stable per-operation identity
carrying that operation's argv. PRD §3.10 requires visible pending items and the exact command per
operation; neither is answerable today. `operation-activity` consumes this projection and MUST NOT
introduce a second, competing notion of operation identity.

The other five requirements — normalized environment, verbatim streaming, terminal result and exit
handling, cancellation escalation, and the Swift 6 baseline — are untouched and byte-identical in the
main spec.

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
(Previously: the same serialization rules, with the operation set held as a private detail — the
queue was neither enumerable nor identity-stable, so pending items and per-operation argv could not
be observed.)

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
