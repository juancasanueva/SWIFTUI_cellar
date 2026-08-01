# Delta for brew-execution

Editorial reconciliation only — no behavioural change. One requirement is modified; its scenarios are
carried over verbatim.

## MODIFIED Requirements

### Requirement: Terminal result and exit handling

An operation MUST end in exactly one terminal outcome: normal exit (any status, including non-zero),
cancelled, spawn failure, or unresponsive cancellation — the last meaning the process did not exit
even after the `SIGTERM` escalation. Exactly two of those outcomes are errors: spawn failure and
unresponsive cancellation. A process that exits — successfully or not — MUST be reported as a
`BrewExit` **value** carrying the exit status and a reason of `exited`; a non-zero status MUST NOT be
raised as a thrown error, because `brew` uses exit codes semantically. A process that stops during
cancellation escalation MUST be reported as cancelled, which is likewise a value and not an error.
The result MUST NOT be delivered before all lines produced by the process are observable.
(Previously: enumerated only three terminal outcomes while the following clause treated unresponsive
cancellation as a fourth, distinct error outcome.)

#### Scenario: Non-zero exit is reported as a value carrying its status

- GIVEN a fake process emitting one stdout line then exiting with code 1
- WHEN the operation completes
- THEN the runner reports `BrewExit(status: 1, reason: .exited)` and nothing is thrown
- AND the emitted line was observable before the exit resolved

#### Scenario: Unlaunchable binary reports spawn failure

- GIVEN a spawner that fails to launch the executable
- WHEN the operation is executed
- THEN it fails with a distinct spawn-failure error and does not crash
