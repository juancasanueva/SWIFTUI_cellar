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

An operation MUST end in exactly one terminal outcome: normal exit (any status, including
non-zero), cancelled, or spawn failure. A process that exits — successfully or not — MUST be
reported as a `BrewExit` **value** carrying the exit status and a reason of `exited`; a non-zero
status MUST NOT be raised as a thrown error, because `brew` uses exit codes semantically. Only
launch faults and an unresponsive cancellation are errors. The result MUST NOT be delivered before
all lines produced by the process are observable.

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
