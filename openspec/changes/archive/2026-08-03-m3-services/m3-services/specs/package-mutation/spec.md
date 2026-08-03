# Delta for package-mutation

Existing capability — `openspec/specs/package-mutation/spec.md` (9 requirements / 34 scenarios).

Delta summary: **4 MODIFIED requirements — 20 scenarios (14 carried forward, 6 added)**. Every
MODIFIED requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED,
REMOVED or RENAMED. 9 requirements / 34 scenarios → **9 requirements / 40 scenarios**.

Services is the first **non-package** mutation family. This slice therefore generalises the shared
mutation spine — the queue, the activity projection, the confirmation gate and the history recorder —
so a second family can enter it without any package rule being loosened. All four amendments below
are strict supersets of the text they replace.

| Req | Change |
|---|---|
| **PM1** "Every mutation is a typed command carrying an explicit kind flag" | "Exactly six" is restated so it survives the shared-abstraction generalisation and forbids a seventh, non-package case |
| **PM4** "A sudo or password prompt is a typed failure" | Widened to every family on the spine, and to brew's **non-fatal** privilege warning on paths that then succeed (gate U5) |
| **PM6** "Every terminal outcome forces one re-snapshot" | **RETITLED**, not merely re-bodied — becomes a **typed invalidation scope** declared by the command; the exactly-once invariant is preserved per declared domain |

> **Instruction to the archive step — PM6 is a rename-in-place.**
>
> The old title is *"Every terminal outcome forces one re-snapshot, and cancel is reported honestly"*
> (`openspec/specs/package-mutation/spec.md`). The new title is *"Every terminal outcome forces one
> refresh of each state domain the command invalidates, and cancel is reported honestly"*.
>
> Archive replaces a MODIFIED requirement by **name**. Because the name changes, promoting this delta
> naively would **add** the new requirement while **leaving the old one in place**, and the main spec
> would then carry two contradictory versions of PM6 — one saying the re-snapshot is unconditional
> and one saying it is scoped. The old-titled requirement MUST be removed in the **same edit** that
> adds the new one.
>
> The capability header prose was reconciled during apply (task 15.2) rather than left to the archive
> step, because header prose sits outside delta scope and would otherwise have survived promotion
> still describing the unconditional re-snapshot.
| **PM7** "No mutation is built or spawned when brew is absent or invalid" | Generalised to every family on the spine |

**Untouched and deliberately so:** PM2 (upgrade scopes), PM3 (confirmation gate — no service verb is
destructive, so no service verb enters it, and the uninstall/zap rule is unchanged), PM5 (typed busy
failure — every new command still serialises behind brew's process-external lock), PM8 (bulk
expansion — services ship **no** bulk affordance in this slice), PM9 (construction validation — the
`-` prefix and whitespace rules stay exactly where they are).

**A product ruling that produces no spec text, recorded so its absence is not read as an oversight**
(Engram `#7182` ruling 4): uninstalling a formula whose service is running **defers to brew**. Cellar
adds no warning and no cross-capability rule, so PM3's confirmation disclosure is untouched on this
point.

## MODIFIED Requirements

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
command, whether it requires confirmation, and the state domains it invalidates — MUST be readable
through that shared abstraction, so no consumer of the spine needs to know which capability a command
came from.
(Previously: the requirement fixed the command count at six but said nothing about how a command from
another capability may reach the shared spine, leaving "add a case" as the path of least resistance.)

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

#### Scenario: An unrecognised failure keeps the raw log

- GIVEN a mutation exiting non-zero with output matching no known signature
- WHEN the operation reaches its terminal outcome
- THEN it is reported as a generic failure
- AND its output remains readable and verbatim, complete up to the documented 2,000-line visible log
  ring, with truncation always marked when that bound is exceeded

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
