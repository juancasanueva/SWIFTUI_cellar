# operation-activity

The observable projection of the brew operation queue: enumerable items with stable identity and
exact argv, copy-command, live per-operation log streaming, cancel from pending and running states,
and the summary and detail projections the activity bar and drawer are driven from. The rules live
in `Packages/CellarCore` target `BrewClient`; the app target holds layout only.

The FIFO gate, the SIGINT→SIGTERM cancellation escalation, and the rule that a mutation cancelled
while queued spawns no process are owned by `brew-execution`. This capability exposes them; it does
not restate or redefine them. Persistence of past operations across launches is out of scope — "for
the session" below means the current app run, with no storage.

## Requirements

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
- THEN its log is still readable, verbatim and in emission order, complete up to the documented
  2,000-line visible ring, with truncation always marked when that bound is exceeded

(Reconciled at archive, 2026-08-02, from verify WARNING 3: the delta said "every emitted line is
still present, verbatim and untruncated". Design D4 deliberately bounds each operation's visible log
to a 2,000-line ring whose 2,001st line evicts the oldest and raises a truncation marker, so
"untruncated" was an unbounded promise the implementation never made and a large `brew upgrade`
would reach in practice. The requirement's "MUST NOT trim, re-encode, reorder, deduplicate, prefix
or annotate lines" clause is unchanged and still binding: it governs per-line fidelity, which is
absolute. The bound is on how many lines stay visible, and it is never silent — `isLogTruncated` is
pinned by the named test "The 2,001st line evicts the oldest and raises the truncation marker". The
same reword is applied to `package-mutation`'s "An unrecognised failure keeps the raw log".)

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

### Requirement: Every terminal outcome records exactly one history entry

When an operation this capability projects reaches a terminal outcome, exactly one history entry MUST
be submitted for it — never zero and never two — carrying that operation's package identity when it
has one, its verb, its exact argv and its outcome. Success, failure and cancellation MUST each be
recorded. Nothing MUST be submitted while the operation is pending or running. Recording MUST be a
side effect: if it is unavailable or fails, the operation's reported outcome, its log, and the
refreshes owed at that outcome MUST be unchanged. What the entry stores and how long it is kept are
owned by `installation-history`.

An operation that reaches a terminal outcome **without ever spawning a process** MUST be treated as a
terminal outcome like any other: no runner configured to execute it, a launch that fails before a
process exists, and an identity the execution layer cannot answer MUST each record exactly one entry
carrying that operation's argv and its failure outcome. This rule MUST hold with no carve-out — a
settled outcome that is reported to the queue but writes no entry is forbidden, whatever path settled
it.

An operation that acts on **no package** MUST be recorded on exactly the same terms: exactly one
entry, carrying no package identity, its own typed verb, its exact argv and its outcome. The absence
of a package identity MUST NOT be a reason to skip the entry, to defer it, or to record a placeholder
or synthesized identity in its place, and MUST NOT change when the entry is written.
(Previously: the requirement was written for operations that carry a package identity and said
nothing about one that does not; and its side-effect clause named "the forced re-snapshot" in the
singular, which no longer matches the per-domain invalidation scope `package-mutation` now declares.)

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
- AND exactly one refresh was forced for each state domain that mutation declared

#### Scenario: An operation with no package identity records exactly one entry

- GIVEN a submitted operation that acts on no package, which reaches a terminal outcome
- WHEN the recorded entries are enumerated
- THEN exactly one entry was submitted for it, carrying its verb, its exact argv and its outcome
- AND that entry carries no package identity, and none was synthesized from its arguments

### Requirement: Activity items carry their source, and their command prefix derives from it

Every enumerated item MUST carry the source of its command. The display command and the copy-command
text MUST be the source's executable name (`brew` or `npm`) followed by the exact argv, in every state,
identical between pending and terminal. The idle summary copy MUST NOT name packages of one source only.
Cancel, log streaming and terminal enumeration MUST be offered on identical terms for both sources.

#### Scenario: An npm item copies and displays as an npm command

- GIVEN a submitted npm upgrade of `typescript`
- WHEN its display command and copy text are read while pending and once terminal
- THEN both are exactly `npm install -g typescript@latest` in both states
- AND the item's source reports npm
- Verification: `unit`

#### Scenario: A brew item is unchanged

- GIVEN a submitted install for the cask `iterm2`
- WHEN its copy text is read
- THEN it is exactly `brew install --cask iterm2`
- Verification: `unit`

#### Scenario: An erased npm item never renders as brew

- GIVEN an npm uninstall erased to the spine's erased type before submission
- WHEN its item is enumerated
- THEN the display command begins with `npm ` and not with `brew `
- Verification: `unit`

## Provenance

- Established by change `m2-mutations-activity` (archived `2026-08-02`, PRD milestone **M2**, slice
  M2-2), ADDED-only delta — **5 requirements / 15 scenarios**, promoted from
  `openspec/changes/archive/2026-08-02-m2-mutations-activity/specs/operation-activity/spec.md`. This
  is the first main spec for the capability; nothing was modified, removed or renamed. This file adds
  the header, the `## Requirements` wrapper, this provenance section, and the one archive
  reconciliation recorded below.
- Binding inputs settled **before** the delta was written, stated in it as facts rather than open
  questions:
  - **PRD §3.10**: every mutation shows the exact `brew` command being run; a global activity view
    streams logs of current and past operations; the queue has visible pending items while read-only
    queries run concurrently; "copy command" everywhere.
  - **Product decision Q6** (user-confirmed 2026-08-02, Engram `#7096`): queue control is
    **cancel-only**. Pending items are visible and cancellable; there is no reorder and no remove.
- **Archive reconciliation — "A terminal operation's log stays readable"** (verify WARNING 3): the
  delta promised the log stays "untruncated" while design D4 bounds the visible log to a 2,000-line
  ring with a truncation marker. Reworded at promotion to state the bound and the always-visible
  marker; per-line fidelity is unchanged and still absolute. The same reword was applied to
  `package-mutation`'s "An unrecognised failure keeps the raw log", so the two capabilities cannot
  drift apart on the same log.
- **Identity is single-sourced from `brew-execution`.** BE1's "Serialized mutations with concurrent
  reads" requires each operation to be assigned a stable identity at submission carrying its exact
  argv; this capability consumes that projection and MUST NOT introduce a second, competing notion of
  operation identity. Duplicate submissions of the same command are permitted by design and are
  distinguished by identity, not deduplicated (verify ruling 3, 2026-08-02).
- **The activity views own no rules.** Every presentation decision the bar, drawer and confirmation
  sheet read — which sentence to show, whether cancel is offered, whether confirmation is required —
  is a computed property in `BrewClient` (design D10), so it is covered by the fast package test loop
  rather than by app-target UI tests.
- **Amended by change `m2-local-metadata-history` (archived `2026-08-03`, PRD milestone **M2**, slice
  M2-3 — the last M2 slice)**: **2 MODIFIED** requirements replaced as whole blocks (adding
  **3 scenarios**) and **1 ADDED** requirement (**4 scenarios**). 5 requirements / 15 scenarios →
  **6 requirements / 22 scenarios**. Nothing was removed or renamed; the other three requirements are
  byte-identical, and both MODIFIED replacements are strict supersets of the text they replaced.
  - **"The operation queue is enumerable, ordered, and carries each operation's argv"** gained the
    rule that the session-long enumeration MUST NOT depend on the execution layer retaining its own
    record, plus 1 scenario. Previously the requirement said a terminal operation remains enumerable
    for the session but did not say where that guarantee is sourced from; the execution layer never
    retired a record, so the distinction had no consequence. M2-3 makes `brew-execution` retire
    terminal, drained records, so without this clause the two capabilities would silently contradict
    each other.
  - **"Cancel is offered from pending and running, and is the only queue control"** gained the
    detached-cancel rule, plus 2 scenarios. This closed M2-2 follow-up 2: a cancel issued while the
    queue was detached from its runner settled the item as cancelled **without signalling the
    process** and paid the mutation gate's `end()` early, after which the still-running operation
    could not be cancelled again. Bulk multi-select, which M2-3 ships, multiplies the exposure — which
    is why the M2-2 archive routed the fix to this slice rather than fixing it speculatively.
  - **"Every terminal outcome records exactly one history entry"** is the new bridge to
    `installation-history`, which owns what is written and how long it is kept. Recording travels
    through a `HistoryRecording` protocol seam whose default is a no-op, so `BrewClient` never links
    SwiftData and a recorder failure is provably inert
    (`OperationCenterHistoryTests > aRecorderFailureNeverReachesTheOperation`, parameterised over
    working / absent / failing recorders).
- ~~**Known follow-up (`m2-local-metadata-history` native review lineage `review-e07590a04c4aff38`,
  WARNING, non-blocking)**: the **no-runner submit path** settles an item as `.launchFailed` without
  going through `finish()`, so that one path produces a terminal outcome with **no** history entry —
  a narrow exception to "Every terminal outcome records exactly one history entry"
  (`OperationCenter.swift:159-163`). It is reachable only when a mutation is submitted while no runner
  is attached.~~ **CLOSED by `m3-hardening-prelude` (M3-0, archived 2026-08-03)** — see the amendment
  below, which promotes the missing guarantee into requirement text rather than leaving it implied.
- **Amended by change `m3-hardening-prelude` (archived `2026-08-03`, PRD milestone **M3**, slice
  M3-0 — the hardening prelude)**: **1 MODIFIED** requirement replaced as a whole block — "Every
  terminal outcome records exactly one history entry" — adding **1 scenario**. 6 requirements / 22
  scenarios → **6 requirements / 23 scenarios**. Nothing was added, removed or renamed; the other
  five requirements are byte-identical, and the replacement is a strict superset of the text it
  replaced. Previously the exactly-one-entry rule was stated for every terminal outcome but was only
  *satisfied* on paths that had spawned a process, so an operation settled without ever spawning
  reached its terminal outcome and recorded **zero** entries — M2-3 follow-up **W1**.
  - **No carve-out was granted** (settled product decision Q4, 2026-08-03, Engram `#7130`): the
    universal rule was kept and the implementation made to honour it, rather than the rule being
    narrowed to spawning paths.
  - Delivered by hoisting `gate?.begin()` **above** the `guard let runner` and routing the no-runner
    branch through `finish(item, with: .launchFailed)` — the single settle site, which already writes
    the entry idempotently — so there is one `begin()` per submit and one `end()` per finish. Pinned
    by `OperationCenterTests > aSubmitWithNoRunnerRecordsExactlyOneHistoryEntry`.
  - **Native review note (lineage `review-fa82e5eaa3023fc4`)**: the reviewer positively verified
    begin/end pairing is structurally sound — every `ActivityItem` is constructed only inside
    `submit`, so no path can reach a terminal outcome outside the funnel.
- **Amended by change `m3-services` (archived `2026-08-03`, PRD milestone **M3**, slice M3-1 —
  Service Management)**: **1 MODIFIED** requirement replaced as a whole block — "Every terminal
  outcome records exactly one history entry" — adding **1 scenario**. 6 requirements / 23 scenarios →
  **6 requirements / 24 scenarios**. Nothing was added, removed or renamed; the other five
  requirements are byte-identical, and the replacement is a strict superset of the text it replaced.
  Services is the first **non-package** operation family, and two things needed saying: what "exactly
  one entry" means for an operation carrying no package identity, and that the side-effect clause's
  "the forced re-snapshot", in the singular, no longer matches the per-domain invalidation scope
  `package-mutation` PM6 now declares.
  - **The absence of a package identity is never a reason to skip, defer, or synthesize.** A
    placeholder or an identity inferred from the argv would have been the path of least resistance and
    is now explicitly forbidden — `installation-history` states the storage half of the same rule.
  - **OA1–OA5 needed no change and were deliberately not reproduced.** OA1 already requires each item
    to carry "the package identity it acts on **when it has one**", so a non-package operation was
    already in contract; copy-command, log streaming, cancel and the summary/detail projections are
    written against the operation rather than against a package, so a service verb gets its own queue
    item, live log, cancel and copy-command for free.
  - **Known follow-up (LOW, non-blocking, found during M3-1 manual verification)**: the collapsed
    activity bar's **idle fallback** reads "No package changes running"
    (`cellar/Activity/ActivityBar.swift:85`), which is now incomplete vocabulary since the bar also
    carries service operations. Verified **not** a misreport — `OperationCenterSummary.runningCommand`
    returns the running item's `displayCommand` for any family, so a live service operation does show
    its own argv; the package-specific wording appears only when nothing is running. Stale copy, not
    a false statement, and deliberately deferred to a vocabulary review when a third family lands.
- **Amended by change `npm-package-source`** (archived `2026-08-30` —
  `openspec/changes/archive/2026-08-30-npm-package-source/`), which closed PRD **M13 — npm package
  source** (`PRD.md` §7 :219-220). **ADDED-only delta — 1 requirement / 3 scenarios**, 0 modified, 0
  removed, 0 renamed, so `rules.archive`'s destructive-delta warning did not fire. The requirement body
  is promoted **byte-identical** from
  `openspec/changes/archive/2026-08-30-npm-package-source/specs/operation-activity/spec.md:12-39`
  (verified by an empty `diff` at archive); this file gained only that block and this bullet.
- **The added requirement is OA7 in file order.** Activity items carry their source, and the display and
  copy string derive their prefix — `brew` or `npm` — from it rather than from a hard-coded literal.
  Pending and terminal presentation is otherwise identical across sources, an **erased** npm item never
  renders as brew, and the idle copy stopped being brew-only.
- **The erasure scenario is the one that matters.** `AnyBrewMutation` copies the source, so a command
  that has lost its concrete type cannot silently reacquire a `brew` prefix on the way to the activity
  log or the clipboard.
