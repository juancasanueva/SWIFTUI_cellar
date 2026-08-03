# Delta for brew-execution

Existing capability — `openspec/specs/brew-execution/spec.md` (6 requirements / 19 scenarios).

Delta summary: **1 MODIFIED requirement — 3 scenarios (2 carried forward unchanged, 1 added)**. The
MODIFIED requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED,
REMOVED or RENAMED.

The requirement enumerates the terminal outcomes an operation may end in, but an identity the
execution layer does not know falls outside all of them and is answered with a fabricated successful
exit. Settled: a typed unknown-operation result, kept a **value** rather than a thrown error so no
caller gains a throwing path, surfaced as a failure. The exactly-one-history-entry obligation for the
resulting terminal outcome is owned by `operation-activity` and referenced here, never restated.

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

An identity the execution layer does not know — one never submitted, or one whose record has already
been retired — MUST yield a typed **unknown-operation** result, distinguishable from every one of the
outcomes above. A successful `BrewExit(status: 0, reason: .exited)` MUST NOT be fabricated for it, and
no other exit status MUST be invented. That result MUST remain a value rather than a thrown error, so
no caller gains a throwing path, and it MUST be surfaced as a failure rather than a success.
(Previously: the requirement enumerated four terminal outcomes and said nothing about an identity the
runner does not know, which was answered with a fabricated `BrewExit(status: 0, reason: .exited)`.)

#### Scenario: Non-zero exit is reported as a value carrying its status

- GIVEN a fake process emitting one stdout line then exiting with code 1
- WHEN the operation completes
- THEN the runner reports `BrewExit(status: 1, reason: .exited)` and nothing is thrown
- AND the emitted line was observable before the exit resolved

#### Scenario: An unknown operation identity yields a typed unknown result

- GIVEN an operation identity the runner was never asked to run
- WHEN its exit is requested
- THEN the answer is a typed unknown-operation result, distinguishable from every exit status
- AND it is not `BrewExit(status: 0, reason: .exited)`, it is surfaced as a failure, and nothing is
  thrown

#### Scenario: Unlaunchable binary reports spawn failure

- GIVEN a spawner that fails to launch the executable
- WHEN the operation is executed
- THEN it fails with a distinct spawn-failure error and does not crash
