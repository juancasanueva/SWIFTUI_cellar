# brew-execution

Executing `brew` as a subprocess: environment normalization, verbatim line-oriented output
streaming, terminal outcomes, cancellation escalation, and the serialized-mutation /
concurrent-read queue. Owned by `Packages/CellarCore` target `BrewProcess`.

## Requirements

### Requirement: Normalized brew environment

Every `brew` invocation MUST run with `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_COLOR=1`,
`HOMEBREW_NO_EMOJI=1`. `HOMEBREW_NO_INSTALL_FROM_API` MUST NOT be set (default API mode).

`HOMEBREW_COLOR` MUST NOT be set to any value, including `"0"`. It is a force-colour boolean whose
mere presence enables ANSI output regardless of value, so setting it to a falsy-looking string
produces the opposite of the intended effect. Colour MUST be disabled through `HOMEBREW_NO_COLOR`
only.

Suppression MUST happen at the source. Because captured output is required to be byte-identical to
what `brew` emitted, the capability MUST NOT strip, filter, rewrite or otherwise post-process escape
bytes out of a captured line in order to satisfy this requirement. Consequently no ESC byte (`0x1B`)
MUST appear in output captured from a `brew` invocation run with this environment.
(Previously: the requirement mandated `HOMEBREW_COLOR=0`, which forces ANSI on rather than off, and
said nothing about where suppression must happen.)

#### Scenario: Environment applied to every invocation

- GIVEN a runner backed by a recording process spawner
- WHEN any command is executed
- THEN the recorded environment contains `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_COLOR=1` and
  `HOMEBREW_NO_EMOJI=1` with those exact values
- AND contains no `HOMEBREW_NO_INSTALL_FROM_API` key

#### Scenario: The force-colour key is never set at any value

- GIVEN the pinned brew environment
- WHEN its keys are enumerated
- THEN no `HOMEBREW_COLOR` key is present, at `"0"` or at any other value

#### Scenario: No ANSI escape byte survives capture

- GIVEN a `brew` invocation executed with the pinned environment and its output captured
  non-interactively
- WHEN every captured line's bytes are inspected
- THEN no line contains the ESC byte `0x1B`
- AND no line was altered, trimmed or re-encoded to achieve that

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

An identity the execution layer does not know — one never submitted, or one whose record has already
been retired — MUST yield a typed **unknown-operation** result, distinguishable from every one of the
outcomes above. A successful `BrewExit(status: 0, reason: .exited)` MUST NOT be fabricated for it, and
no other exit status MUST be invented. That result MUST remain a value rather than a thrown error, so
no caller gains a throwing path, and it MUST be surfaced as a failure rather than a success.

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

Retention of those records MUST be bounded: they MUST NOT accumulate for the lifetime of the process.
A record MUST be retired only once its operation is terminal **and** its result has been drained, so
the operation's exit MUST remain answerable for any operation still being awaited, and retiring a
record MUST never affect a pending or running operation. A retired operation MUST NOT be reported as
pending or running by the enumeration, and MUST NOT be re-spawned, re-queued or resurrected in any
form.

An operation's observable phase MUST NOT be republished when its value has not changed, so observers
see one change per real transition rather than one per yield.

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
- **Amended by change `m2-local-metadata-history` (archived `2026-08-03`, PRD milestone **M2**, slice
  M2-3 — the last M2 slice)**: **1 MODIFIED** requirement replaced as a whole block — "Serialized
  mutations with concurrent reads" — adding **4 scenarios**. 6 requirements / 15 scenarios →
  **6 requirements / 19 scenarios**. Nothing was added, removed or renamed; the other five
  requirements are byte-identical, and the amendment is a strict superset of the text it replaced.
  Previously the records were retained for the whole process lifetime with no retirement rule at all,
  and the queue phase was published on every yield without an equality guard. This closed M2-2
  follow-up 4, which the M2-2 archive routed here as a **hard prerequisite** for
  `installation-history`: a durable history is dishonest if the in-memory execution records it is
  derived alongside grow without bound.
  - **Retirement is ownership-based, not time-based** (design D6). `BrewOperation.deinit` calls
    `release(_:)`, and `evictRetiredRecords()` retires only records that are both compacted and
    released, sorted by ordinal, dropping only the overflow past
    `BrewRunner.defaultRetainedTerminalRecords == 200`. The cap is injectable purely as a test seam
    (`retainedTerminalRecords: 0` makes retirement observable without a 260-operation loop); the
    shipped default is the pinned 200.
  - **`exit(of:)` stays answerable for anything still awaited.** A compacted record still answers its
    exit and its fault — pinned by `RetentionTests > aTerminalRecordAnswersExitAfterItsExecutionResourcesAreReleased`
    and `aCompactedRecordStillAnswersFault`.
- **`operation-activity` states the other half of the retirement contract.** Its amended "The
  operation queue is enumerable, ordered, and carries each operation's argv" says a retired execution
  record does not remove its queue item, so the session-long projection survives this bound. The two
  clauses were written in the same change to be read together and MUST NOT drift.
- ~~**Known follow-up (`m2-local-metadata-history` native review lineage `review-e07590a04c4aff38`,
  SUGGESTION, non-blocking)**: `exit(of:)` answers an *unknown* operation id with a fabricated
  `BrewExit(status: 0)` rather than a typed "unknown operation" result; only the `isReleased` gate
  prevents that value from being observed today.~~ **CLOSED by `m3-hardening-prelude` (M3-0, archived
  2026-08-03)** — see the amendment below.
- **Amended by change `m3-hardening-prelude` (archived `2026-08-03`, PRD milestone **M3**, slice
  M3-0 — the hardening prelude)**: **1 MODIFIED** requirement replaced as a whole block — "Terminal
  result and exit handling" — adding **1 scenario**. 6 requirements / 19 scenarios → **6 requirements
  / 20 scenarios**. Nothing was added, removed or renamed; the other five requirements are
  byte-identical, and the replacement is a strict superset of the text it replaced. Previously the
  requirement enumerated four terminal outcomes and said nothing about an identity the runner does
  not know, which `exit(of:)` answered with a fabricated `BrewExit(status: 0, reason: .exited)` —
  M2-3 follow-up **S1**.
  - **The result stayed a value, not a thrown error** (settled at proposal): `exit(of:)` reaches
    ~30 call sites through `BrewOperation.exit()`, and making it throwing would have given every one
    of them a throwing path for a condition none of them can act on.
  - Delivered as `case unknownOperation` **inside** the `BrewExit.Reason` declaration — a Swift enum
    case cannot be added in an extension, so the design sketch's extension form was invalid — plus
    `BrewExit.unknownOperation = BrewExit(status: -1, reason: .unknownOperation)`. `-1` cannot
    collide with a wait status (0–255) or a signalled `128+n`, and because `isSuccess` is
    `reason == .exited && status == 0`, the fabricated success is now **unrepresentable by
    construction** rather than merely avoided. It classifies to the **existing**
    `MutationOutcome.launchFailed` ("the process never started"), so no new outcome case, message or
    `summaryLabel` was introduced. Pinned by `ExitTests >
    anUnknownOperationYieldsATypedUnknownResultRatherThanSuccess` and
    `UnknownOperationTests > anUnknownOperationClassifiesAsLaunchFailedNotSucceeded`.
  - **Native review note (lineage `review-fa82e5eaa3023fc4`)**: the reviewer positively verified the
    `.unknownOperation` decision is made **before** the stderr scan, so no fault classification can
    re-fabricate a success from it.
- **Amended by change `m3-services` (archived `2026-08-03`, PRD milestone **M3**, slice M3-1 —
  Service Management)**: **1 MODIFIED** requirement replaced as a whole block — "Normalized brew
  environment" — adding **2 scenarios**. 6 requirements / 20 scenarios → **6 requirements / 22
  scenarios**. Nothing was added, removed or renamed; the other five requirements are byte-identical,
  and the replacement is a strict superset of the text it replaced. **The shipped requirement
  mandated the exact opposite of its own stated intent**: it named `HOMEBREW_COLOR=0` verbatim while
  `HOMEBREW_COLOR` is a *force-colour* boolean in brew (`Library/Homebrew/env_config.rb:249-252`,
  declared `disabled_by: :HOMEBREW_NO_COLOR`) whose mere **presence** enables ANSI regardless of
  value — so Cellar was forcing colour on and then capturing the escape bytes (defect Engram `#7179`).
  - **Confirmed by a three-way `od -c` probe**, not by reading the source alone: under
    `HOMEBREW_COLOR=0` the captured bytes carry `\033[34m==>\033[0m` even with stdout redirected to a
    file, while `HOMEBREW_NO_COLOR=1` comes back clean. Re-confirmed on brew 6.0.15 during apply on
    this slice's own `brew services list` command: 0 ESC bytes under the new key, 3 ESC-carrying lines
    under the old one.
  - **Suppression is required to happen at the source, and stripping is now explicitly forbidden.**
    "Verbatim line-oriented output streaming" requires a line containing ANSI bytes to be delivered
    byte-identically, so a future change that "fixed" colour by filtering ESC bytes in the core would
    satisfy this requirement while silently breaking that one. The amendment says so in requirement
    text rather than leaving it to reviewer memory.
  - Delivered as a one-key change in `BrewEnvironment.swift` — `pinned["HOMEBREW_COLOR"] = "0"`
    became `pinned["HOMEBREW_NO_COLOR"] = "1"` — plus the doc comment that asserted the opposite of
    the shipped behaviour. Pinned by `theForceColourKeyIsNeverSetAtAnyValue`, by a spawned-process
    assertion through `RecordingProcessLauncher`, and by a self-skipping **integration** test that
    runs a real `brew info --formula <discovered>` and asserts no `0x1B` byte survives capture. A
    fake process cannot prove anything about brew's own colour decision, which is why the integration
    half exists.
  - **"Terminal result and exit handling" was deliberately NOT re-modified.** M2-3 follow-up **S1**
    was already closed by `m3-hardening-prelude` above; the umbrella explore's §3 row listing it as
    M3 work was stale. Re-modifying it would have been a no-op block carrying regression risk.
  - **"Serialized mutations with concurrent reads" is unchanged and load-bearing.** Every command
    family this slice introduces is a mutation and inherits the existing FIFO gate, the read/mutation
    split, the SIGINT→SIGTERM escalation and the SIGKILL ban verbatim.
