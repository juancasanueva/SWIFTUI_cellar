# brew-execution

Executing `brew` as a subprocess: environment normalization, verbatim line-oriented output
streaming, terminal outcomes, cancellation escalation, and the serialized-mutation /
concurrent-read queue. Owned by `Packages/CellarCore` target `BrewProcess`.

## Requirements

### Requirement: Normalized brew environment

Every `brew` invocation MUST run with `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_COLOR=0`,
`HOMEBREW_NO_EMOJI=1`. `HOMEBREW_NO_INSTALL_FROM_API` MUST NOT be set (default API mode).

#### Scenario: Environment applied to every invocation

- GIVEN a runner backed by a recording process spawner
- WHEN any command is executed
- THEN the recorded environment contains the three variables with those exact values
- AND contains no `HOMEBREW_NO_INSTALL_FROM_API` key

### Requirement: Verbatim line-oriented output streaming

Output MUST be delivered as a stream of `LogLine` values whose text is byte-identical to what
`brew` emitted. The core MUST NOT trim, re-encode, normalize, prefix, or annotate lines. Each line
MUST be tagged as `stdout` or `stderr`. Emission order MUST be preserved as read.

#### Scenario: Line content is preserved exactly

- GIVEN a fake process emitting a line with leading whitespace, emoji, and ANSI bytes
- WHEN the caller consumes the stream
- THEN the received `LogLine` text equals the emitted bytes exactly

#### Scenario: stdout and stderr are distinguishable and interleaved in read order

- GIVEN a fake process emitting stdout "a", stderr "b", stdout "c"
- WHEN the caller consumes the stream
- THEN it receives exactly `[(stdout,"a"), (stderr,"b"), (stdout,"c")]` in that order

#### Scenario: Stream finishes after process termination

- GIVEN a running operation
- WHEN the process terminates
- THEN the stream finishes and yields no further values

### Requirement: Terminal result and exit handling

An operation MUST end in exactly one terminal outcome: normal exit (any status, including non-zero),
cancelled, spawn failure, or unresponsive cancellation — the last meaning the process did not exit
even after the `SIGTERM` escalation. Exactly two of those outcomes are errors: spawn failure and
unresponsive cancellation. A process that exits — successfully or not — MUST be reported as a
`BrewExit` **value** carrying the exit status and a reason of `exited`; a non-zero status MUST NOT be
raised as a thrown error, because `brew` uses exit codes semantically. A process that stops during
cancellation escalation MUST be reported as cancelled, which is likewise a value and not an error.
The result MUST NOT be delivered before all lines produced by the process are observable.

#### Scenario: Non-zero exit is reported as a value carrying its status

- GIVEN a fake process emitting one stdout line then exiting with code 1
- WHEN the operation completes
- THEN the runner reports `BrewExit(status: 1, reason: .exited)` and nothing is thrown
- AND the emitted line was observable before the exit resolved

#### Scenario: Unlaunchable binary reports spawn failure

- GIVEN a spawner that fails to launch the executable
- WHEN the operation is executed
- THEN it fails with a distinct spawn-failure error and does not crash

### Requirement: Cancellation escalates SIGINT then SIGTERM

Cancellation MUST first deliver `SIGINT`. If the process has not exited within the grace deadline,
`SIGTERM` MUST follow. The outcome MUST be reported as cancelled, never as failure. Cancelling the
consuming Swift task MUST trigger the same escalation.

#### Scenario: Cooperative process stops at SIGINT

- GIVEN a fake process that exits when it receives `SIGINT`
- WHEN the operation is cancelled
- THEN only `SIGINT` was delivered and the outcome is cancelled

#### Scenario: Unresponsive process is escalated to SIGTERM

- GIVEN a fake process that ignores `SIGINT`
- WHEN the operation is cancelled and the grace deadline elapses
- THEN `SIGTERM` is delivered after `SIGINT` and the outcome is cancelled

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

### Requirement: Swift 6 concurrency and platform baseline

The capability MUST build under Swift 6 language mode with strict concurrency and no warnings.
Every type crossing an isolation boundary (`LogLine`, results, errors, configuration) MUST be
`Sendable`. The deployment floor is macOS 26.0, Apple Silicon only; no `#available` branches.

#### Scenario: Package builds and tests headlessly under Swift 6

- GIVEN the CellarCore package in Swift 6 language mode with strict concurrency
- WHEN `swift test --package-path Packages/CellarCore` runs without Xcode or a GUI
- THEN it builds with zero concurrency warnings and all tests pass

## Provenance

- Established by change `m1-brewrunner-core` (archived `2026-08-01`), ADDED-only delta —
  `openspec/changes/archive/2026-08-01-m1-brewrunner-core/specs/brew-execution/spec.md`.
- **Archive amendment (W2, 2026-08-01)**: "Terminal result and exit handling" and its first
  scenario previously said a non-zero exit "fails with an error carrying exit code 1". Amended to
  value semantics — the runner reports `BrewExit(status:reason:)` and does not throw — matching
  approved design decision D3 and the shipped implementation.
- **Editorial reconciliation (change `m1-catalog-browse`, 2026-08-01)**: "Terminal result and exit
  handling" enumerated three terminal outcomes while the following clause treated unresponsive
  cancellation as a fourth. Amended to name all four explicitly and to state which two are errors.
  No behavioural change; scenarios carried over verbatim.
- **Amended by change `m2-mutations-activity` (archived `2026-08-02`, PRD milestone **M2**, slice
  M2-2)**: **1 MODIFIED** requirement replaced as a whole block — "Serialized mutations with
  concurrent reads" — adding **3 scenarios**. 6 requirements / 12 scenarios → **6 requirements / 15
  scenarios**. Nothing was added, removed or renamed; the other five requirements are byte-identical.
  Previously the requirement stated only the serialization rules and held the operation set as a
  private runner detail: the queue was neither enumerable nor identity-stable, so pending items and
  per-operation argv could not be observed at all. PRD §3.10 requires visible pending items and the
  exact command per operation, and neither was answerable. The amendment is **purely additive
  observability**: the FIFO gate, the read/mutation split, the SIGINT→SIGTERM escalation and the
  SIGKILL ban (M1 D3/D4) are unchanged, and the implementation stores only `command` and `ordinal`
  per record — operation phase is *derived* from the process and resolved exit, never stored twice,
  so it cannot drift.
- **`operation-activity` consumes this projection and must not fork it.** That capability's
  "The operation queue is enumerable, ordered, and carries each operation's argv" is written as a
  consumer of the identity established here; it MUST NOT introduce a second, competing notion of
  operation identity. Duplicate submissions of the same command are permitted and are told apart by
  identity rather than deduplicated (`m2-mutations-activity` verify ruling 3, 2026-08-02) — which is
  exactly what "MUST distinguish two otherwise identical submissions" buys.
