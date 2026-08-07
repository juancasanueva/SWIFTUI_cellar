# package-mutation

Changing the installed set through `brew`: the six typed mutating commands and the argv they
generate, the three upgrade scopes, the destructive-action confirmation gate, the typed sudo and
external-lock failures, the **typed invalidation scope each command declares** and the honest cancel
reporting owed at every terminal outcome, and refusing to mutate when brew is absent. Owned by
`Packages/CellarCore` target `BrewClient` — the only target that sees both `BrewProcess` and
`Catalog`, one-directionally.

This capability also owns the **shared mutation spine** — the queue, the activity projection, the
confirmation gate and the history recorder — which other capabilities' commands enter through a
shared abstraction rather than as additional cases of this capability's own command type. A command
that does not declare the installed set forces no inventory re-snapshot at any terminal outcome; the
exactly-once obligation is per declared domain, not unconditional.

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

This capability's mutating-command type MUST continue to carry exactly those six commands and no
others. The shared mutation spine MAY carry commands belonging to other capabilities, and every such
command MUST enter it through a shared abstraction rather than as an additional case of this
capability's command type. Adding a non-package verb as a seventh case is forbidden, because that
type's identity, verb and argv are package-shaped by construction. Everything the spine needs from a
command — its argv, its verb, the package identity it acts on **when it has one**, its display
command, whether it requires confirmation, the state domains it invalidates, and **the confirmation
disclosure it carries** — MUST be readable through that shared abstraction, so no consumer of the
spine needs to know which capability a command came from.

The disclosure MUST be part of that abstraction rather than recovered from a concrete command type.
No consumer of the spine MUST derive a disclosure by downcasting, type-testing, switching on a
command case, or inspecting a verb string; a command that declares no disclosure of its own MUST
supply the ordinary package-removal disclosure by default rather than by a caller's fallback. A
batch's disclosure MUST be derived from the commands themselves — the first submitted command's
disclosure, which is the command the confirmation leads with — so a batch presents the same
disclosure whether its commands were submitted as a concrete type or as erased values. Erasure MUST
NOT change, downgrade or discard a disclosure. This rule governs the **disclosure** only: it does not
disturb the separate typed cleanup evidence a confirmation may additionally carry, and it does not
forbid reading a command's verb for a presentation concern that is not the disclosure, such as the
shipped retitling of a zap confirmation.
(Previously: the enumerated list of projections readable through the shared abstraction omitted the
confirmation disclosure, so the spine recovered it by downcasting to a concrete command type and an
erased batch silently fell back to the package-removal disclosure — defeating a typed warning that
another capability owns.)

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

#### Scenario: Another family enters the spine without becoming a case of this type

- GIVEN a command belonging to a different capability, submitted through the shared mutation spine
- WHEN this capability's mutating-command type is enumerated
- THEN it still carries exactly the six package commands, with no case for that other command
- AND the submitted command was still projected with its argv, its verb and its terminal outcome

#### Scenario: An erased mixed batch still discloses tap trust

- GIVEN a batch whose first command is a tap add and whose remaining commands are installs, erased
  to the spine's erased command type before submission
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the tap-trust disclosure for that tap
- AND it is identical to the disclosure the same tap add presents when submitted unerased

#### Scenario: An erased install-only batch still discloses package removal

- GIVEN a batch of package mutations only, erased before submission
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the ordinary package-removal disclosure
- AND no tap-trust or force-untap disclosure is presented

#### Scenario: No disclosure is recovered by a type test

- GIVEN every consumer of the shared mutation spine that presents a confirmation
- WHEN the path that produces the disclosure is inspected
- THEN the disclosure is read from the command through the shared abstraction
- AND no downcast, type test, case switch or verb-string inspection produces it

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

Within this capability's six package mutations, uninstall and uninstall with `--zap` MUST require an
explicit confirmation before anything is submitted to the queue. The confirmation MUST display the
exact command that will run, matching the operation's argv character for character. Zap MUST be a
separate, separately-confirmed choice and MUST NOT be implied by an ordinary uninstall. Install,
reinstall, upgrade, pin and unpin MUST NOT require confirmation. Declining a confirmation MUST spawn
no process, submit nothing to the queue, and leave the inventory untouched.

A bulk uninstall MUST be confirmed once for the whole selection, and that single confirmation MUST
name every package it will remove — not a count alone and not an elided subset. Confirming it MUST
submit the whole selection; declining it MUST submit none of it, never a partial subset.

The shared confirmation gate MUST additionally carry the typed tap-add trust disclosure and typed
force-untap affected-package disclosure owned by `tap-management` TM6 and TM8. Every tap add and every
force untap MUST be confirmed; plain untap MUST NOT require confirmation or be made forceful
implicitly. The exact command MUST come from the typed mutation request. Warning text, rendered
command text, package disclosure, and persisted history text MUST never be parsed to construct or
modify argv. A stale force disclosure MUST be rejected before process spawn on the freshness terms of
TM8 and MUST require a new confirmation.

(Previously: confirmation covered package uninstall, zap, and bulk uninstall only; the shared gate
had no typed trust or force-untap disclosure and no stale-disclosure rejection rule.)

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

#### Scenario: A bulk uninstall confirmation names every selected package

- GIVEN a selection of the formulae `wget` and `git` and the cask `iterm2`
- WHEN a bulk uninstall is requested
- THEN exactly one confirmation is requested before anything is submitted
- AND the text it presents names all three packages

#### Scenario: Declining a bulk uninstall submits none of it

- GIVEN a pending bulk uninstall confirmation over three packages
- WHEN it is declined
- THEN no process is spawned and no operation is enqueued for any of the three

#### Scenario: Every tap add carries typed trust disclosure

- GIVEN a valid tap-add request
- WHEN it reaches the shared confirmation gate
- THEN confirmation carries the typed tap identity, exact command, and third-party code warning
- AND declining submits nothing

#### Scenario: Force untap carries typed complete package disclosure

- GIVEN an eligible force untap affecting formulae and casks
- WHEN it reaches the shared confirmation gate
- THEN every affected package and kind is carried without elision or count-only substitution
- AND plain untap remains a distinct non-force request

#### Scenario: Stale disclosure and display text cannot become argv

- GIVEN a force disclosure whose affected set changes while open or queued
- WHEN confirmation reaches submission
- THEN it is rejected before spawn and requires a refreshed confirmation
- AND neither display text nor stored text is parsed into a replacement argv

### Requirement: A sudo or password prompt is a typed failure, never an interactive prompt

Mutations MUST run with standard input connected to `/dev/null`. The capability MUST NOT prompt for,
collect, store or forward a password, and MUST NOT escalate privileges by any means. When a
mutation's output carries a password or sudo prompt signature, the operation MUST end in a distinct
typed failure that names the package, echoes the exact command, and directs the user to run that one
command in Terminal. It MUST NOT be reported as a generic error, MUST NOT be retried automatically,
and MUST NOT be presented as a Cellar defect. Output matching no known signature MUST fall back to
the ordinary failure surface with the raw log preserved verbatim.

These rules MUST hold for every command submitted through the shared mutation spine, not only for
package mutations: no family MAY open an interactive stdin, prompt for credentials, or escalate
privileges.

The typed sudo failure MUST additionally require that the operation actually **failed**. Privilege
wording that appears in the output of an operation which reaches a **successful** terminal outcome
MUST NOT be classified as the typed sudo failure, because `brew` emits non-fatal privilege warnings
on paths that then succeed — a service registered into the user domain after a
"must be run as root to start at system startup!" warning is a success, not a sudo-required failure.
An operation that failed with output matching no known signature MUST be reported as a generic
failure with its raw log preserved, and MUST NEVER be reported as a success.
(Previously: the rule was scoped to package mutations, and classification keyed on the signature
alone without requiring the operation to have failed — so a non-fatal privilege warning on a
successful run could be surfaced as a sudo-required failure.)

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

#### Scenario: A non-fatal privilege warning on a successful run is not a sudo failure

- GIVEN an operation whose output contains the privilege warning
  "must be run as root to start at system startup!" and which then exits with status 0
- WHEN it reaches its terminal outcome
- THEN it is reported as successful, not as the typed sudo-required failure
- AND no Terminal guidance is surfaced for it

#### Scenario: A non-package operation runs with the same non-interactive stdin

- GIVEN a command from another family submitted through the shared mutation spine
- WHEN the process it spawns is observed
- THEN that process's standard input is the null device
- AND no password input surface was offered to the user

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

### Requirement: Every terminal outcome forces one refresh of each state domain the command invalidates, and cancel is reported honestly

Every command submitted through the mutation spine MUST declare the set of state domains it
invalidates. That declaration MUST be carried by the **command**, MUST be readable before the
operation is submitted, MUST NOT be derived from the outcome, and MUST NOT be a single unconditional
value shared by every command.

Success, failure — including the typed sudo and busy failures — and cancellation MUST each force
exactly one refresh of **each state domain the command declares**: never zero and never two, for
each declared domain. A command that does not declare the installed set MUST NOT force an
installed-inventory re-snapshot at any terminal outcome, because a probe that cannot observe a change
is pure cost. A command that declares no domain at all MUST still reach its terminal outcome, MUST
still record its history entry, and MUST still report its outcome on exactly the same terms.

A cancelled mutation MUST be reported with one generic message stating that brew may have left a
partial change and that the affected state is being refreshed. That message MUST NOT be tailored per
command, and MUST NOT claim the change was rolled back, that nothing happened, or that the package is
in a known state.
(Previously: every terminal outcome forced exactly one **inventory** re-snapshot unconditionally, so
a command that cannot change the installed set had no way to opt out and paid a full
`brew info --installed --json=v2` probe it could never learn anything from.)

#### Scenario: A successful mutation refreshes each declared domain exactly once

- GIVEN a mutation declaring the installed set, that exits with status 0
- WHEN it reaches its terminal outcome
- THEN exactly one inventory re-snapshot is forced

#### Scenario: A failed mutation still refreshes what it declared

- GIVEN a mutation declaring the installed set that exits non-zero, and separately one that ends in
  the typed busy failure
- WHEN each reaches its terminal outcome
- THEN exactly one inventory re-snapshot is forced for each

#### Scenario: A cancelled mutation refreshes and admits partial state

- GIVEN a running mutation declaring the installed set
- WHEN it is cancelled and reaches the cancelled outcome
- THEN exactly one inventory re-snapshot is forced
- AND the reported message is the same generic partial-state message for every command, and does not
  claim the change was undone

#### Scenario: A command that does not declare the installed set takes no inventory snapshot

- GIVEN a command whose declared invalidation scope does not include the installed set
- WHEN it reaches a successful terminal outcome
- THEN no `brew info --installed --json=v2` invocation was recorded
- AND exactly one refresh was forced for each domain it did declare

#### Scenario: A failed or cancelled non-inventory command still refreshes what it declared

- GIVEN a command declaring one non-inventory domain, run once to a non-zero exit and once to
  cancellation
- WHEN each reaches its terminal outcome
- THEN exactly one refresh of that declared domain is forced in each case
- AND still no inventory re-snapshot is forced

### Requirement: No mutation is built or spawned when brew is absent or invalid

When brew detection reports absent, invalid, or a missing configured path, the capability MUST NOT
spawn any mutation. Mutation affordances MUST be unavailable rather than failing at spawn time,
nothing MUST be thrown or blocked, and the same read-only guidance the inventory surfaces MUST
apply. When brew later becomes available, mutations MUST become available without restarting the
app.

This rule MUST hold for every command family submitted through the mutation spine, not only for
package mutations. Each family's own surface MUST render the same read-only guidance rather than
failing at spawn time, MUST spawn nothing while brew is absent or invalid, and MUST become available
again when brew appears without restarting the app.
(Previously: the rule was written for package mutations only, so a new family's availability
behaviour was unspecified.)

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

#### Scenario: A non-package family is equally unavailable when brew is absent

- GIVEN brew detection reports absent
- WHEN a command from another family is requested through the shared mutation spine
- THEN no process is spawned and nothing is thrown
- AND that family's affordance reports itself unavailable with the same read-only guidance

### Requirement: A bulk selection expands to one invocation per selected package

A bulk upgrade or bulk uninstall over a selection MUST expand into one operation per selected
package, each naming exactly that one package with its own kind flag, enqueued in selection order and
serialized through the existing mutation gate. No generated argv MUST name more than one package, so
kind mixing is structurally impossible and every selected package gets its own queue item, log,
copy-command, cancel and terminal outcome. A failure or cancellation of one operation MUST NOT cancel
or suppress the remaining operations in the batch, and MUST attribute to exactly one package. Bulk
expansion MUST be offered for upgrade and uninstall only; no other verb MUST accept a selection.

#### Scenario: A bulk uninstall expands to one invocation per package

- GIVEN a confirmed bulk uninstall over the formulae `wget` and `git` and the cask `iterm2`, in that
  order
- WHEN the mutations are built
- THEN exactly three operations are enqueued, with the argvs `uninstall --formula wget`,
  `uninstall --formula git` and `uninstall --cask iterm2`, in that order
- AND no argv names more than one package

#### Scenario: A mid-batch failure attributes to one package and does not stop the batch

- GIVEN a bulk action over three packages where the second operation exits non-zero
- WHEN all three reach their terminal outcomes
- THEN the failure is reported against the second package only
- AND the third operation still ran

#### Scenario: Cancelling one operation of a batch leaves the rest queued

- GIVEN a bulk action over three packages with the first running and the other two pending
- WHEN the second is cancelled
- THEN the second is reported cancelled and spawned no process
- AND the third still runs after the first completes

#### Scenario: No other verb accepts a selection

- GIVEN a non-empty selection
- WHEN the mutation surface is asked to build pin, unpin or reinstall mutations for it
- THEN no such bulk mutation is available

### Requirement: Every mutation command is validated at construction, with no bypass

A mutation command MUST be constructible only through a path that validates the package identity it
names, so the by-construction validation claim holds at every call site with no exception. A name
that is empty, that is only whitespace, or that begins with `-` — which would otherwise be
interpreted by brew as an option rather than a package — MUST be rejected at construction and MUST
NOT reach the queue or a spawned process. No alternate constructor, initializer or convenience
overload MUST exist that produces a command from an unvalidated identity.

A name that originated in a **file supplied by the user** — an imported Brewfile — is subject to
exactly these rules and to no weaker ones. The premise this requirement was written under, that a
name reaches it from brew's own snapshot or from the catalog and never from free text, no longer
holds once a user-supplied file is a name source; it is restated here rather than left stale. A
file-sourced name MUST become a command only by constructing the same validated typed identity every
other call site constructs. A name that typed identity refuses MUST be reported by its caller as a
typed, counted refusal, and MUST NOT reach the queue, an argv, or a spawned process by any other
path. No file-sourced-name convenience constructor MUST exist, no "already validated" bypass MUST
exist, and no path MUST carry a raw string read out of a file into argv.

(Previously: the requirement governed construction generally while assuming every name arrived from
brew's own snapshot or from the catalog, and said nothing about a name originating in a
user-supplied file.)

#### Scenario: An empty or whitespace name is rejected

- GIVEN package identities whose names are the empty string and a single space
- WHEN a mutation command is constructed for each
- THEN construction fails for both and no operation is enqueued

#### Scenario: A name that looks like an option is rejected

- GIVEN a package identity named `--force`
- WHEN a mutation command is constructed for it
- THEN construction fails
- AND no argv containing `--force` was produced or spawned

#### Scenario: No construction path skips validation

- GIVEN the public construction surface of the mutation command type
- WHEN every way to obtain a command instance is enumerated
- THEN each one applies the same identity validation

#### Scenario: A file-sourced name is validated on exactly the same terms

- GIVEN names read out of an imported Brewfile, including `--force`, `wget; rm -rf /`, the empty
  string and a single space
- WHEN a mutation command is constructed for each
- THEN construction fails for every one of them
- AND none reaches the queue, and no argv containing any of those strings was produced or spawned

#### Scenario: No path carries a raw file-sourced string into argv

- GIVEN the public construction surface and every call site that builds a command from an imported
  Brewfile
- WHEN they are enumerated
- THEN every file-sourced name passes through the same validated typed identity as every other name
- AND no constructor, overload or bypass accepts an unvalidated string read from a file

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
- **Amended by change `m2-local-metadata-history` (archived `2026-08-03`, PRD milestone **M2**, slice
  M2-3 — the last M2 slice)**: **1 MODIFIED** requirement replaced as a whole block (adding
  **2 scenarios**) and **2 ADDED** requirements (**7 scenarios**). 7 requirements / 25 scenarios →
  **9 requirements / 34 scenarios**. Nothing was removed or renamed; the other six requirements are
  byte-identical, and the MODIFIED replacement is a strict superset of the text it replaced.
  - **"Uninstall and zap are the only mutations behind a confirmation gate"** gained the bulk-uninstall
    disclosure rule: one confirmation for the whole selection, naming **every** package it will remove
    — not a count and not an elided subset — with confirming submitting all of it and declining
    submitting none. Previously the requirement governed single-package uninstall and zap only and said
    nothing about what a confirmation covering several packages must disclose or submit. Delivered as
    a `ConfirmationRequest` storing head + tail (`command` + `additional`) so non-emptiness is a
    **type fact**, with `confirm(_:)` returning `[ActivityItem]`.
  - **"A bulk selection expands to one invocation per selected package"** extends the M2-2
    upgrade-selected ruling (Engram `#7101`) to uninstall on the same terms — per-package attribution,
    log, copy-command, cancel and terminal outcome, and a mid-batch failure attributing to exactly one
    package. Upgrade and uninstall are the only bulk-eligible verbs (settled 2026-08-02); the
    restriction is proven exhaustively over `BulkSelection.Action.allCases`, not by convention.
  - **"Every mutation command is validated at construction, with no bypass"** closed M2-2 follow-up 3:
    `MutationMenu.swift` and `PackageDetailView.swift` built commands from a raw, unvalidated
    `PackageID`, which made `MutationCommand`'s by-construction validation claim untrue at exactly
    those two sites. Delivered as a `PackageTarget` wrapper with a failable init, so **no enum case
    takes a bare `PackageID`** — a compiler fact, asserted by
    `MutationCommandTargetTests > noEnumCaseTakesABarePackageID`. The rule itself lives in exactly one
    place (`MutationName.isSafe` at `MutationCommand.swift:104-107`: non-empty, no leading `-`, no
    whitespace), pinned by `theSafetyRuleIsDefinedOnce`.
  - **The `-` prefix rejection is new in this slice.** The M2-2 spec forbade empty and whitespace-only
    names; option-injection hardening (a name such as `--force` reaching argv) was tightened here and
    is triangulated over 10 hostile names × 3 constructors.
- **`installed-inventory` owns the selection model; this capability owns its expansion.** The
  selection's order, its reconciliation against the inventory, and which verbs offer a bulk affordance
  are specified there. `installation-history` owns the durable record each terminal outcome writes.
- **Amended by change `m3-services` (archived `2026-08-03`, PRD milestone **M3**, slice M3-1 —
  Service Management)**: **4 MODIFIED** requirements replaced as whole blocks — "Every mutation is a
  typed command carrying an explicit kind flag" (PM1), "A sudo or password prompt is a typed failure,
  never an interactive prompt" (PM4), "Every terminal outcome forces one re-snapshot, and cancel is
  reported honestly" (PM6) and "No mutation is built or spawned when brew is absent or invalid"
  (PM7) — adding **6 scenarios**. 9 requirements / 34 scenarios → **9 requirements / 40 scenarios**.
  Nothing was added or removed; all four replacements are strict supersets of the text they replaced.
  Services is the first **non-package** mutation family, so this slice generalised the shared mutation
  spine — the queue, the activity projection, the confirmation gate and the history recorder — so a
  second family can enter it **without any package rule being loosened**.
  - **PM6 was RENAMED IN PLACE, not merely re-bodied.** Its title changed from "Every terminal outcome
    forces one re-snapshot, and cancel is reported honestly" to "Every terminal outcome forces one
    refresh of each state domain the command invalidates, and cancel is reported honestly". Because
    promotion replaces a MODIFIED requirement by **name**, a naive promotion would have *added* the
    new requirement while *leaving the old one in place*, and this spec would have carried two
    contradictory versions of PM6 — one saying the re-snapshot is unconditional and one saying it is
    scoped. The old-titled block was removed in the **same edit** that added the new one, and the
    absence of the old title was verified after promotion.
  - **The invalidation scope is carried by the COMMAND, declared before submission, never derived from
    the outcome.** `MutationOutcome.forcesReSnapshot` was **deleted** — what a command invalidates is
    a property of what ran, not of how it ended. The exactly-once invariant is preserved **per
    declared domain**, including failed and cancelled terminals. `installed-inventory` II10 and
    `installation-history` IH7 state the other halves of the same contract and were amended in the
    same change so the three cannot drift.
  - **PM1's "exactly six" stays literally true by construction.** `ServiceCommand` enters the spine
    through a shared `BrewMutating` abstraction rather than as a seventh case, and `MutationCommand`
    conforms in a three-line extension supplying only `invalidates`. The protocol is `Sendable`-only —
    a `Self`-requiring `Equatable` protocol would have broken the stored `ActivityItem.command` and
    `ConfirmationRequest: Equatable`'s four shipped assertions — and the erased `AnyBrewMutation`
    stores only the six projections, which *strengthens* rather than weakens the shipped "nothing is
    parsed back out of a command" property. `submit` is **generic, not existential**, so every
    existing app-target call site compiled unchanged.
  - **PM4 now requires the operation to have actually failed** before the typed sudo failure applies.
    Gate U5 established from source that a root-domain start as a non-root user never invokes sudo and
    cannot reach a password prompt: brew emits a non-fatal "must be run as root to start at system
    startup!" warning and then installs into the **user** domain. Without this clause a run that
    emitted that warning and then exited 0 would have been surfaced as a sudo-required failure.
  - **The capability header prose was reconciled during apply**, not at archive: it described the
    unconditional re-snapshot at every terminal outcome, sits outside delta scope, and would otherwise
    have survived promotion still contradicting the amended PM6.
  - **PM2, PM3, PM5, PM8 and PM9 are untouched and byte-identical.** No service verb is destructive,
    so none enters the confirmation gate; services ship no bulk affordance; and PM9's construction
    rules stay exactly where they are — `ServiceTarget` is expressed over the **same**
    `MutationName.isSafe` gate as `PackageTarget` rather than widening it. Shell metacharacters are
    neutralised structurally rather than by rejection: argv is a vector and no shell exists, pinned by
    `shellMetacharactersSurviveAsOneLiteralArgument` driving `$(whoami)`, `atuin;rm`, `` `id` ``,
    `a|b`, `a&b` and `a>b` through the real process seam.
  - **A product ruling that produces no spec text, recorded so its absence is not read as an
    oversight** (Engram `#7182` ruling 4): uninstalling a formula whose service is running **defers to
    brew**. Cellar adds no warning and no cross-capability rule, so PM3's confirmation disclosure is
    untouched on this point.
- **Amended by change `m3-taps` (archived `2026-08-05`, PRD milestone **M3**, slice M3-2 — Tap
  Management)**: **1 MODIFIED** requirement replaced as a whole-block strict superset — PM3 — adding
  typed tap-add trust disclosure, typed force-untap package disclosure, plain-untap separation, and
  queue-front stale-disclosure rejection. 9 requirements / 40 scenarios → **9 requirements / 43
  scenarios**.
- **Amended by change `m5-brewfile` (archived `2026-08-07`, PRD milestone **M5** "Pro-parity flows",
  slice 4 of 5 — Brewfile import & export)**: **2 MODIFIED** requirements — PM1 and PM9 — each
  replaced as a whole block, adding **5 scenarios**. 9 requirements / 43 scenarios → **9 requirements
  / 48 scenarios**. Nothing was added, removed or renamed; the other seven requirements are
  byte-identical, and both replacements are strict supersets of the text they replaced, verified at
  archive by byte-slicing the replaced ranges rather than by assertion — all six of PM1's original
  scenarios and all three of PM9's are carried through verbatim, and no package rule is loosened.
  - **PM1 — a security-relevant disclosure that did not survive erasure.** PM1 already required that
    everything the spine needs from a command be readable *through the shared abstraction*. Design
    (`design.md`, Engram `#7523`, decision **DD1**) checked that claim against shipped source and
    found one projection outside it: the confirmation disclosure.
    `OperationCenterBulk.swift:141` recovered it by concrete-type downcast —
    `(first as? TapCommand)?.disclosure ?? .packageRemoval` — while `AnyBrewMutation`
    (`BrewMutating.swift:144-162`) carried only seven projections, `disclosure` among neither them
    nor the `BrewMutating` requirements. Every shipped call site happened to submit an unerased
    `TapCommand`, so **the gap never fired**; a Brewfile batch is the first mixed tap+install
    submission and must be erased to `[AnyBrewMutation]`, at which point the downcast fails and the
    sheet silently shows the package-removal disclosure instead of the tap-trust warning that
    `tap-management` owns. It was fixed as a requirement, not as an implementation detail: the
    disclosure is now an enumerated projection, deriving one by downcast, type test, case switch or
    verb-string inspection is forbidden, a command declaring none supplies `.packageRemoval` by
    protocol default rather than by a caller's fallback, and erasure MUST NOT change, downgrade or
    discard it. Delivered exactly as DD1 specified — `disclosure` promoted to a `BrewMutating`
    requirement with a `.packageRemoval` extension default, carried as `AnyBrewMutation`'s eighth
    stored projection, and `request` reading `first.disclosure`. Verified in source at archive:
    `rg 'as\? *TapCommand'` finds **zero** executable occurrences (4 hits = 3 doc comments + 1
    structural guard scanning for the string). Blast radius was measured as **zero** shipped test
    edits. **Rejected:** splitting the batch into two requests, which would raise two confirmations
    and let a declined tap still install its packages, breaking all-or-nothing; and a new
    `BrewfileMutation` conformer, which the proposal forbids and which would still fail the downcast.
  - **The rule is scoped to the disclosure and nothing else.** It explicitly does not disturb the
    separate typed cleanup evidence a confirmation may additionally carry, and it explicitly does not
    forbid the shipped `isZap` verb read, which retitles a zap confirmation — a presentation concern,
    not a disclosure.
  - **PM1's rolling `(Previously:)` annotation was replaced, not lost.** The note m3-services left on
    PM1 (that the requirement fixed the command count at six but said nothing about how another
    capability's command may reach the shared spine) was superseded by this slice's note about the
    disclosure, following the one-rolling-note-per-block convention. Its substance is preserved in
    the m3-services entry above; the five deleted lines at promotion were those two annotation lines
    plus the three-line projection-list sentence, rewrapped only to add the disclosure to the
    enumeration. No normative clause was removed.
  - **PM9 — the provenance premise stopped being true, so it was restated rather than left stale.**
    The reasoning block at the head of `MutationCommand.swift` argues from "names come from brew's
    own snapshot or from the catalog, never from free text". An imported Brewfile is a user-supplied
    file and it is a name source, so that premise no longer holds. PM9 now says a file-sourced name is
    subject to exactly these rules and to no weaker ones, becomes a command only by constructing the
    same validated typed identity every other call site constructs, and that a refused name is a
    typed counted refusal reaching no queue, argv or process by any other path. No file-sourced
    convenience constructor and no "already validated" bypass may exist.
  - **Nothing was widened to make this work, and that is the load-bearing part.** `MutationName.isSafe`
    (`MutationCommand.swift:104-108`) is **unchanged**: it rejects empty, leading `-` and whitespace,
    so `/` already passed and a tap-prefixed `brew "user/repo/token"` was already representable. The
    parser added a *narrower* file-boundary grammar rather than relaxing the shipped gate.
    `MutationCommand.swift` received a comment-only provenance restatement with **zero changed
    executable lines**. `CatalogFileSystem` was reused unwidened. `Package.swift` and
    `project.pbxproj` have zero-line diffs.
  - **`brewfile-management` owns the file; this capability still owns the spine.** A Brewfile
    selection becomes existing typed commands — `TapCommand.addTap` and `MutationCommand.install` —
    with no new `BrewMutating` conformer, no seventh case, and no new invalidation domain. Because
    the confirmation gate derives a batch's disclosure from its **first** command, the new
    capability's tap-before-install ordering rule is what makes a mixed batch present tap trust; the
    two requirements are deliberately coupled and were promoted in the same archive so they cannot
    drift.
