# Delta for operation-activity

New capability — there is no `openspec/specs/operation-activity/spec.md` yet, so this delta is
ADDED-only. Nothing is MODIFIED, REMOVED or RENAMED anywhere in this file.

Delta summary: **5 ADDED requirements / 15 scenarios.**

Scope: the observable projection of the operation queue (enumerable items, stable identity, argv
echo), copy-command, live per-operation log streaming, cancel from pending and running states, and
the summary/detail projections the activity bar and drawer are driven from.

Binding inputs, already settled — stated here as facts, not open questions:

- PRD §3.10: every mutation shows the exact `brew` command being run; a global activity view streams
  logs of current and past operations; the queue has visible pending items while read-only queries
  run concurrently; "copy command" everywhere.
- Product decision Q6 (Engram `sdd/m2-mutations-activity/product-decisions-extended`): queue control
  is **cancel-only**. Pending items are visible and cancellable; there is no reorder and no remove.

Deliberately not specified here: the FIFO gate, the SIGINT→SIGTERM escalation, and the rule that a
mutation cancelled while queued spawns no process are owned by `brew-execution`. This capability
exposes them; it does not restate or redefine them. Persistence of past operations across launches
is out of scope (M2-3) — "for the session" below means the current app run, with no storage.

## ADDED Requirements

### Requirement: The operation queue is enumerable, ordered, and carries each operation's argv

Every submitted operation MUST be projected as an enumerable item carrying a stable identity, the
package identity it acts on when it has one, its exact argv, its state — pending, running, or
terminal — and, once terminal, its outcome. The identity MUST be assigned at submission and MUST NOT
change as the operation moves between states, so an observer can follow one operation across its
whole lifetime. Pending operations MUST be enumerated in the order brew will actually run them.
A terminal operation MUST remain enumerable for the rest of the session. Enumerating MUST be
read-only: it MUST NOT start, delay, reorder or otherwise perturb any operation.

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

### Requirement: Copy command yields exactly the command that runs

Every enumerated operation MUST offer a copy-command action producing exactly the command that was
or will be run. The copied text MUST correspond to the operation's argv with no added, removed or
reordered arguments, no truncation, and no decoration beyond what makes it pasteable into a
terminal. Copying MUST be available in every state, including pending and terminal, and MUST produce
the same text in each.

#### Scenario: The copied text matches the argv

- GIVEN a submitted install for the cask `iterm2`
- WHEN its copy-command text is produced
- THEN it is exactly `brew install --cask iterm2`

#### Scenario: Copying a pending operation matches copying it later

- GIVEN a pending mutation whose copy text is captured
- WHEN the operation runs and reaches a terminal outcome and its copy text is captured again
- THEN the two texts are identical

### Requirement: Logs stream live per operation and are preserved verbatim

Each running operation MUST expose its output as it arrives, not only once it has finished. Lines
MUST be presented verbatim, tagged as stdout or stderr, and in the order emitted — matching the
streaming contract owned by `brew-execution`. This capability MUST NOT trim, re-encode, reorder,
deduplicate, prefix or annotate lines. A terminal operation's log MUST remain readable for the rest
of the session.

#### Scenario: Lines appear while the operation is still running

- GIVEN a running mutation whose fake process has emitted two lines and has not exited
- WHEN the operation's log is read
- THEN both lines are already present
- AND the operation is still reported as running

#### Scenario: Order and stream tagging survive the projection

- GIVEN a process emitting stdout "a", stderr "b", stdout "c"
- WHEN the operation's log is read
- THEN it contains exactly those three lines, with those stream tags, in that order

#### Scenario: A terminal operation's log stays readable

- GIVEN a mutation that emitted lines and then exited
- WHEN its log is read after the terminal outcome
- THEN every emitted line is still present, verbatim and untruncated

### Requirement: Cancel is offered from pending and running, and is the only queue control

Cancel MUST be offered for pending operations and for the running one. Cancelling a pending
operation MUST resolve it as cancelled without spawning any process — the guarantee owned by
`brew-execution`, which this capability exposes rather than re-implements. Cancelling the running
operation MUST use the existing cancellation escalation and MUST be reported as cancelled, never as
a failure, and the next pending operation MUST then start. This capability MUST NOT offer reordering
or removal of queued operations, and the queue order MUST NOT be mutable from any surface it
exposes.

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

### Requirement: Summary and detail projections come from one source of truth

The capability MUST expose a summary projection — whether any work is in flight, the operation
currently running, and the number of pending operations — suitable for an always-visible activity
indicator, and a detail projection listing every enumerated operation with its state, argv and log.
Both MUST be derived from the same queue projection so they cannot disagree. When nothing is queued
or running, the summary MUST report idle and MUST NOT claim work is in progress.

#### Scenario: The summary reports the running operation and the pending count

- GIVEN mutation A running with mutations B and C pending
- WHEN the summary projection is read
- THEN it reports work in flight, names A as running, and reports a pending count of 2

#### Scenario: An empty queue reports idle

- GIVEN no operation has been submitted, and separately every submitted operation has reached a
  terminal outcome
- WHEN the summary projection is read
- THEN it reports idle in both cases and reports a pending count of 0

#### Scenario: Summary and detail never disagree

- GIVEN any sequence of submissions, cancellations and terminal outcomes
- WHEN the summary's running operation and pending count are compared with the detail listing
- THEN the summary's running operation is the one the detail lists as running
- AND the summary's pending count equals the number of operations the detail lists as pending
