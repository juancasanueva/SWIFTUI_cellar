# package-mutation

Changing the installed set through `brew`: the six typed mutating commands and the argv they
generate, the three upgrade scopes, the destructive-action confirmation gate, the typed sudo and
external-lock failures, the forced inventory re-snapshot and honest cancel reporting at every
terminal outcome, and refusing to mutate when brew is absent. Owned by `Packages/CellarCore` target
`BrewClient` — the only target that sees both `BrewProcess` and `Catalog`, one-directionally.

Process spawning, output streaming, cancellation escalation and queue serialization belong to
`brew-execution` and are referenced here, never restated. Queue presentation belongs to
`operation-activity`.

## Requirements

### Requirement: Every mutation is a typed command carrying an explicit kind flag

The capability MUST expose exactly six mutating commands — install, uninstall, reinstall, upgrade,
pin and unpin — each built from the `(kind, name)` package identity already used by the catalog and
the inventory. Every generated argv MUST pass the kind explicitly as `--formula` or `--cask` and
MUST NOT rely on brew's token disambiguation, because a token such as `docker` exists in both
namespaces. A single invocation MUST NOT carry both kind flags. The argv MUST be inspectable before
the operation is submitted, and the argv actually spawned MUST be identical to the inspected one.

#### Scenario: Installing a formula names it as a formula

- GIVEN the formula `wget`
- WHEN an install mutation is built for it
- THEN the argv is exactly `install --formula wget`

#### Scenario: Installing a cask names it as a cask

- GIVEN the cask `iterm2`
- WHEN an install mutation is built for it
- THEN the argv is exactly `install --cask iterm2`

#### Scenario: Uninstalling a cask names it as a cask

- GIVEN the installed cask `iterm2`
- WHEN an uninstall mutation is built for it
- THEN the argv is exactly `uninstall --cask iterm2`

#### Scenario: Reinstall, pin and unpin carry the kind flag too

- GIVEN the installed formula `git`
- WHEN reinstall, pin and unpin mutations are built for it
- THEN their argvs are exactly `reinstall --formula git`, `pin --formula git` and
  `unpin --formula git`

#### Scenario: A token that exists in both namespaces is never ambiguous

- GIVEN `docker` exists as both a formula and a cask
- WHEN an install mutation is built for the cask `docker`
- THEN the argv contains `--cask` and does not contain `--formula`
- AND the spawned command is the cask install, not the formula install

### Requirement: Upgrade has three scopes and follows brew's own defaults

Upgrade MUST be offered for a single package, for an explicit selection, and for everything.
A single upgrade MUST name exactly that package with its kind flag. A selected upgrade MUST expand
into one operation per selected package, each naming exactly that one package with its own kind
flag, enqueued in selection order and serialized through the existing mutation gate; it MUST NOT
group several packages into one invocation, so kind mixing is structurally impossible and every
selected package gets its own queue item, log, copy-command, cancel and terminal outcome.
"Upgrade all" MUST be a plain `brew upgrade` with no package arguments and no kind flag,
inheriting brew's defaults: pinned packages are skipped and auto-updating casks are excluded. The
capability MUST NOT pass `--greedy`, `--greedy-latest`, `--greedy-auto-updates` or `--force` to
defeat those defaults, and MUST NOT unpin anything in order to upgrade it. The exclusion of
self-updating casks MUST agree with the outdated derivation owned by `installed-inventory`.

#### Scenario: A single upgrade names one package

- GIVEN the outdated formula `wget`
- WHEN a single-package upgrade is built for it
- THEN the argv is exactly `upgrade --formula wget`

#### Scenario: A selected upgrade expands to one invocation per package

- GIVEN a selection of the formulae `wget` and `git` and the cask `iterm2`, in that order
- WHEN a selected upgrade is built
- THEN exactly three operations are enqueued, with the argvs `upgrade --formula wget`,
  `upgrade --formula git` and `upgrade --cask iterm2`, in that order
- AND no argv names more than one package

#### Scenario: Upgrade all is a bare brew upgrade

- GIVEN any inventory
- WHEN an upgrade-all mutation is built
- THEN the argv is exactly `upgrade`
- AND it contains no package name, no kind flag, no `--greedy` variant and no `--force`

#### Scenario: A pinned package is never force-upgraded

- GIVEN an inventory containing a pinned formula
- WHEN upgrade-all and a selected upgrade over the outdated set are built
- THEN the pinned formula is not named in either argv
- AND no unpin mutation is submitted on its behalf

### Requirement: Uninstall and zap are the only mutations behind a confirmation gate

Uninstall, and uninstall with `--zap`, MUST require an explicit confirmation before anything is
submitted to the queue. The confirmation MUST display the exact command that will run, matching the
operation's argv character for character. Zap MUST be a separate, separately-confirmed choice and
MUST NOT be implied by an ordinary uninstall. Install, reinstall, upgrade, pin and unpin MUST NOT
require confirmation. Declining a confirmation MUST spawn no process, submit nothing to the queue,
and leave the inventory untouched.

#### Scenario: Uninstall asks first and shows the exact command

- GIVEN the installed formula `wget`
- WHEN an uninstall is requested
- THEN a confirmation is requested before anything is submitted
- AND the text it presents contains exactly `brew uninstall --formula wget`

#### Scenario: Declining spawns nothing

- GIVEN a pending uninstall confirmation
- WHEN it is declined
- THEN no process is spawned and no operation is enqueued

#### Scenario: Zap is confirmed separately and shows its own command

- GIVEN the installed cask `iterm2`
- WHEN a zap is requested
- THEN a confirmation distinct from the plain uninstall is requested
- AND the command it presents contains `--zap`

#### Scenario: Non-destructive mutations run without confirmation

- GIVEN the formula `wget`
- WHEN install, upgrade, pin and unpin mutations are requested for it
- THEN no confirmation is requested for any of them
- AND each is submitted to the queue directly

### Requirement: A sudo or password prompt is a typed failure, never an interactive prompt

Mutations MUST run with standard input connected to `/dev/null`. The capability MUST NOT prompt for,
collect, store or forward a password, and MUST NOT escalate privileges by any means. When a
mutation's output carries a password or sudo prompt signature, the operation MUST end in a distinct
typed failure that names the package, echoes the exact command, and directs the user to run that one
command in Terminal. It MUST NOT be reported as a generic error, MUST NOT be retried automatically,
and MUST NOT be presented as a Cellar defect. Output matching no known signature MUST fall back to
the ordinary failure surface with the raw log preserved verbatim.

#### Scenario: A cask that asks for a password fails with Terminal guidance

- GIVEN a mutation whose output contains a sudo password prompt signature and which then exits
  non-zero
- WHEN the operation reaches its terminal outcome
- THEN it is reported as the typed sudo-required failure, not a generic failure
- AND the surfaced guidance contains the exact command to run in Terminal

#### Scenario: Standard input is never interactive

- GIVEN any mutation executed by the capability
- WHEN the process it spawns is observed
- THEN that process's standard input is the null device, so no prompt could be answered from it
- AND no password input surface was offered to the user

(Reconciled at archive, 2026-08-02, from verify WARNING 2: the delta wrote this scenario as
"GIVEN a recording process spawner … THEN the recorded standard input for the process is
`/dev/null`". The `ProcessSpec` seam carries no standard-input field, so a recording launcher
structurally cannot observe one and the scenario as written was untestable at that seam. The
behaviour is implemented at the composition root — `SystemProcess.swift` sets
`standardInput = FileHandle.nullDevice` on every spawned process, untouched M1 code. The scenario
now asserts the observable behaviour and no longer names a seam field that does not exist. The
requirement text is unchanged. See follow-up 8 in the M2-2 archive report for the optional
`ProcessSpec` carry-through that would make the original wording directly testable.)

#### Scenario: An unrecognised failure keeps the raw log

- GIVEN a mutation exiting non-zero with output matching no known signature
- WHEN the operation reaches its terminal outcome
- THEN it is reported as a generic failure
- AND its output remains readable and verbatim, complete up to the documented 2,000-line visible log
  ring, with truncation always marked when that bound is exceeded

(Reconciled at archive, 2026-08-02, from verify WARNING 3: the delta said "verbatim and
untruncated". Design D4 deliberately caps each operation's visible log at a 2,000-line ring whose
2,001st line evicts the oldest and raises a truncation marker, so "untruncated" was an unbounded
promise the implementation never made. No line is ever mutilated, re-encoded, reordered or
annotated — the bound is on how many lines stay visible, and it is never silent. The same reword is
applied to `operation-activity`'s "A terminal operation's log stays readable".)

### Requirement: An external brew lock is a typed busy failure

A mutation that exits non-zero with output matching brew's lock-conflict signature — `has already
locked` and/or `Please wait for it to finish or terminate it to continue` — MUST be reported as a
distinct busy failure telling the user Homebrew is busy in another terminal and to retry when it
finishes. The command name brew embeds in that message describes the invocation that was blocked,
not the process holding the lock; the capability MUST NOT parse a holder out of the message and MUST
NOT present any command as the blocking process. A busy failure MUST NOT be retried automatically,
and MUST NOT suppress the forced re-snapshot owed at a terminal outcome. A non-zero exit without the
signature MUST NOT be classified as busy.

#### Scenario: A lock conflict is reported as busy, not as a generic failure

- GIVEN a mutation that exits with status 1 and emits on stderr the line
  "Error: A \`brew uninstall hello\` process has already locked /opt/homebrew/Cellar/hello."
  followed by "Please wait for it to finish or terminate it to continue."
- WHEN the operation reaches its terminal outcome
- THEN it is reported as the typed busy failure
- AND its message tells the user Homebrew is busy in another terminal

#### Scenario: The lock holder is never named from brew's message

- GIVEN the same busy failure
- WHEN its user-facing message is inspected
- THEN it does not present the command name embedded in brew's message, or any other command parsed
  out of it, as the process holding the lock

#### Scenario: A non-zero exit without the signature is not busy

- GIVEN a mutation exiting with status 1 and output containing neither lock phrase
- WHEN the operation reaches its terminal outcome
- THEN it is reported as a generic failure, not as busy

### Requirement: Every terminal outcome forces one re-snapshot, and cancel is reported honestly

Success, failure — including the typed sudo and busy failures — and cancellation MUST each force
exactly one inventory re-snapshot at the terminal outcome, never zero and never two. A cancelled
mutation MUST be reported with one generic message stating that brew may have left a partial change
and that the inventory is being refreshed. That message MUST NOT be tailored per command, and MUST
NOT claim the change was rolled back, that nothing happened, or that the package is in a known
state.

#### Scenario: A successful mutation refreshes the inventory exactly once

- GIVEN a mutation that exits with status 0
- WHEN it reaches its terminal outcome
- THEN exactly one inventory re-snapshot is forced

#### Scenario: A failed mutation still refreshes the inventory

- GIVEN a mutation that exits non-zero, and separately a mutation that ends in the typed busy
  failure
- WHEN each reaches its terminal outcome
- THEN exactly one inventory re-snapshot is forced for each

#### Scenario: A cancelled mutation refreshes and admits partial state

- GIVEN a running mutation
- WHEN it is cancelled and reaches the cancelled outcome
- THEN exactly one inventory re-snapshot is forced
- AND the reported message is the same generic partial-state message for every command, and does not
  claim the change was undone

### Requirement: No mutation is built or spawned when brew is absent or invalid

When brew detection reports absent, invalid, or a missing configured path, the capability MUST NOT
spawn any mutation. Mutation affordances MUST be unavailable rather than failing at spawn time,
nothing MUST be thrown or blocked, and the same read-only guidance the inventory surfaces MUST
apply. When brew later becomes available, mutations MUST become available without restarting the
app.

#### Scenario: Absent brew spawns nothing

- GIVEN brew detection reports absent
- WHEN a mutation is requested for any package
- THEN no process is spawned and nothing is thrown
- AND the mutation affordance reports itself unavailable

#### Scenario: An invalid configured path is guidance, not failure

- GIVEN brew detection reports an invalid configured path
- WHEN a mutation is requested
- THEN no process is spawned
- AND the rejection reason is available as read-only guidance

#### Scenario: Mutations become available when brew appears

- GIVEN mutations are unavailable because detection reported absent
- WHEN detection transitions to a valid installation
- THEN a mutation requested afterwards is built and submitted normally

## Provenance

- Established by change `m2-mutations-activity` (archived `2026-08-02`, PRD milestone **M2**, slice
  M2-2), ADDED-only delta — **7 requirements / 25 scenarios**, promoted from
  `openspec/changes/archive/2026-08-02-m2-mutations-activity/specs/package-mutation/spec.md`. This is
  the first main spec for the capability; nothing was modified, removed or renamed. This file adds
  the header, the `## Requirements` wrapper, this provenance section, and the two archive
  reconciliations recorded below.
- Binding inputs settled **before** the delta was written, stated in it as facts rather than open
  questions:
  - **Product decisions** (user-confirmed 2026-08-02, Engram `#7094` Q1–Q4 and `#7096` Q5–Q7):
    sudo-requiring casks are detected and explained, never escalated; confirmation is for uninstall
    and zap only; "upgrade all" is a plain `brew upgrade` matching brew's own defaults; cancel
    messaging is generic; queue control is cancel-only; an external lock conflict is a typed busy
    failure.
  - **Upgrade-selected ruling** (user, 2026-08-02, Engram `#7101`): a selected upgrade enqueues one
    brew invocation **per selected package**, not one grouped invocation per kind. The reason is
    attribution — each selected package gets its own queue item, log, copy-command, cancel and
    terminal outcome, and a mid-batch failure attributes to exactly one package. "Upgrade all" is the
    deliberate exception and stays one grouped, flagless, nameless invocation. This superseded the
    spec's first draft, which grouped selected upgrades by kind.
  - **Live lock probe** (brew 6.0.14, Engram `#7097`): a lock conflict exits 1 with
    `Error: A ... process has already locked ...` plus `Please wait for it to finish or terminate it
    to continue.` on stderr. The command name brew embeds in that message describes the *current*
    invocation, not the process actually holding the lock — which is why "An external brew lock is a
    typed busy failure" forbids parsing a holder out of it. The naive parse would confidently name
    the wrong process.
  - **Live pin/unpin probe** (brew 6.0.14): `brew pin --help` and `brew unpin --help` both document
    `--formula, --formulae` and `--cask, --casks`, so the explicit kind flag is required on all six
    package-naming verbs with **no per-verb exception**.
- **Archive reconciliation 1 — "Standard input is never interactive"** (verify WARNING 2): the
  delta's scenario named a `ProcessSpec` recording seam that carries no standard-input field, so the
  scenario was untestable exactly as written even though the behaviour ships correctly at
  `SystemProcess.swift` (`standardInput = FileHandle.nullDevice`). The scenario was reworded at
  promotion to assert the observable behaviour without naming a field that does not exist. The
  requirement text ("Mutations MUST run with standard input connected to `/dev/null`") is unchanged
  and remains the binding rule. The scenario's second clause — no credential surface — was already
  fully covered.
- **Archive reconciliation 2 — "An unrecognised failure keeps the raw log"** (verify WARNING 3): the
  delta promised the log stays "untruncated" while design D4 deliberately bounds each operation's
  visible log to a 2,000-line ring with a truncation marker. The promise was unbounded in a way the
  implementation never claimed and a large `brew upgrade` would reach in practice. Reworded at
  promotion to state the bound and the always-visible marker. The requirement's "raw log preserved
  verbatim" clause is unchanged, because no per-line mutilation, re-encoding, reordering or
  annotation occurs — the bound is on visible line count only, and it is never silent
  (`isLogTruncated`).
- **`brew-execution` owns the mechanism, this capability owns the vocabulary.** Serialization,
  streaming, cancellation escalation and the SIGKILL ban are referenced, never restated, so a future
  change cannot fork a second execution policy under this capability's name.
