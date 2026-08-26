# service-management

Enumerating the background services Homebrew manages, polling their status while the services surface
is visible, exposing each service's plist and log locations, and running the four service verbs
through the shared mutation spine. Owned by `Packages/CellarCore`.

`brew` is the sole source of truth for service state. This capability MUST NOT read or write launchd
state directly, and MUST NOT model a service as a package: a service is its own entity with its own
identity, and `service` MUST NOT enter the installed-package projection.

Process spawning, output streaming, cancellation escalation and queue serialization belong to
`brew-execution`. Serialized submission, the confirmation gate, the typed sudo and busy failures, the
invalidation-scope declaration and the brew-absent rule belong to `package-mutation` and are
referenced here, never restated. The exactly-one-history-entry obligation belongs to
`operation-activity`; what that entry stores belongs to `installation-history`.

## Requirements

### Requirement: The service list comes from one probe, decoded tolerantly

A services refresh MUST acquire its data from exactly one `brew services list --json` invocation, and
its argv MUST be exactly `services list --json`. The payload MUST be decoded as an array of records,
each carrying at least a name, a status, an optionally-null user, an optionally-null exit code and a
plist file path. A null user or a null exit code MUST decode as **absent**, never as an error and
never as a fabricated default.

The status MUST be decoded over the seven values `started`, `none`, `scheduled`, `stopped`, `error`,
`unknown` and `other`. An unrecognised status string MUST map to a catch-all case that preserves the
raw string, MUST NOT fail the record, and MUST NOT fail the payload. A record that cannot be decoded
at all MUST be skipped rather than failing the whole payload. Decoding MUST run off the main actor.

#### Scenario: One invocation per refresh, with the exact argv

- GIVEN a fake process launcher recording every invocation
- WHEN one services refresh completes
- THEN exactly one brew invocation was recorded
- AND its arguments are exactly `services list --json`

#### Scenario: All seven statuses decode

- GIVEN a fixture payload carrying one record for each of `started`, `none`, `scheduled`, `stopped`,
  `error`, `unknown` and `other`
- WHEN the payload is decoded
- THEN seven services are listed, each with its own distinct status

#### Scenario: An unrecognised status never fails the payload

- GIVEN a fixture payload of three records, one of which carries the status string `mystery`
- WHEN the payload is decoded
- THEN all three services are listed
- AND the third reports a catch-all status that preserves the raw string `mystery`

#### Scenario: Null user and null exit code decode as absent

- GIVEN a record whose `user` and `exit_code` are both JSON null
- WHEN it is decoded
- THEN the service is listed with no user and no exit code
- AND nothing was thrown and no default value was substituted

### Requirement: Service detail is fetched lazily for the selected service only

The plist location, the log path and the error-log path MUST come from `brew services info --json`
for a single named service. That probe MUST run only when a service is selected, MUST name exactly
that one service, and MUST NOT use `--all`. It MUST NOT run on a poll tick and MUST NOT run for
services that are not selected.

Optional keys in that payload are emitted as **null** rather than omitted, and MUST decode as absent.
When the log path and the error-log path resolve to the same file, the capability MUST present that
location once rather than twice; when they differ, both MUST be presented. A service that declares no
log location MUST be presented as having none, and MUST NOT show an empty or placeholder path.

#### Scenario: Detail is fetched only for the selected service

- GIVEN a services list of three services and a fake process launcher recording every invocation
- WHEN one service is selected
- THEN exactly one additional brew invocation is recorded, naming exactly that service
- AND no invocation carries `--all`

#### Scenario: A poll tick fetches no detail

- GIVEN a visible services surface with no service selected
- WHEN several poll ticks elapse
- THEN every recorded invocation is the list probe
- AND no `services info` invocation was recorded

#### Scenario: Null optional keys decode as absent

- GIVEN an info payload whose `log_path`, `error_log_path` and `pid` are all JSON null
- WHEN it is decoded
- THEN the service reports no log location, no error-log location and no process id
- AND nothing was thrown

#### Scenario: Identical log and error-log paths are presented once

- GIVEN an info payload whose `log_path` and `error_log_path` are the same file path
- WHEN the service's log locations are read
- THEN exactly one log location is presented
- AND when the two paths differ, both are presented

### Requirement: The services surface polls only while visible, on an injected clock

The services list MUST refresh once when the services surface becomes visible, and MUST then refresh
every 5 seconds for as long as it stays visible. The cadence MUST be driven by an injected clock, so
it is provable without wall-clock sleeps.

Polling MUST stop **entirely** — not slow down — when the surface stops being visible, whether
because the window was hidden or because the section was deselected. No poll MUST run while the
surface is not visible. At most one services poll loop MUST run per app launch, regardless of how
many windows are opened or closed.

Polling MUST be suppressed while a service mutation is in flight, so a restart in progress cannot
produce a flickering status. The refresh owed at a service mutation's terminal outcome is required by
"A service operation invalidates services state only" and MUST NOT be duplicated by the poll.

A **secondary read-only surface** — one that presents services state without being the services section
— MAY perform **exactly one baseline refresh** when it appears. Such a surface MUST NOT report
visibility to the coordinator that owns the poll: the visibility conjunction that gates the poll MUST
keep exactly the halves it has today, so a secondary surface can neither start a poll nor keep one alive
after the section itself stops being visible. It MUST NOT start, extend, restart or reschedule a poll of
any cadence, and MUST schedule nothing on the injected clock. Its one refresh MUST be **skipped
entirely** while a service mutation is in flight, on the same terms as the poll and for the same reason,
and MUST NOT be deferred to run at that mutation's terminal outcome, which already owes its own refresh.
Such a surface presents last-known state; a state it cannot obtain MUST read as ordinary last-known
state rather than as an error.
(Previously: the requirement described visibility solely as the services section's own — one refresh on
becoming visible followed by a 5-second cadence — and named exactly two reasons a surface stops being
visible. A read-only surface that shows services state without being that section had no described home,
so it could only overload the shared visibility boolean and leave the poll running past the section's
own disappearance, or show nothing current at all.)

#### Scenario: The list refreshes on the poll cadence while visible

- GIVEN a visible services surface and an injected clock
- WHEN the clock is advanced by 5 seconds three times
- THEN one baseline refresh plus exactly three further refreshes were performed
- AND no wall-clock sleep was required to observe them

#### Scenario: Hiding the surface stops polling entirely

- GIVEN a visible services surface that has already polled at least once
- WHEN the surface stops being visible and the clock is then advanced by 60 seconds
- THEN no further brew invocation is recorded
- AND polling resumes with a baseline refresh when it becomes visible again

#### Scenario: Only one poll loop runs per launch

- GIVEN the app has launched with the services surface visible
- WHEN a second window is opened, then all windows are closed and a new one is opened
- THEN exactly one services poll loop is running throughout

#### Scenario: Polling is suppressed while a service mutation is in flight

- GIVEN a visible services surface and a service mutation in flight
- WHEN the clock is advanced past several poll intervals before that mutation reaches its terminal
  outcome
- THEN no poll refresh ran while the mutation was in flight
- AND exactly one refresh ran at the mutation's terminal outcome

#### Scenario: A secondary read-only surface refreshes once, reports nothing, and starts no poll

- GIVEN a services section that is not visible, an injected clock, and a secondary read-only surface
- WHEN that surface appears and the clock is then advanced by 60 seconds
- THEN exactly one refresh was performed, at its appearance, and advancing the clock produced no further
  brew invocation
- AND no visibility was reported, so the poll's gating conjunction is unchanged and no poll loop started
- AND when the same surface appears while a service mutation is in flight, no refresh runs at all and
  none is deferred to that mutation's terminal outcome
- Verification: `unit`

### Requirement: Exactly four service verbs, one invocation per service

The capability MUST expose exactly four service verbs — `start`, `stop`, `restart` and `run` — each
naming exactly one service. A verb's argv MUST be exactly `services <verb> <name>`.

No generated argv MUST contain `--all`, so every service gets its own queue item, its own log, its
own copy-command, its own cancel and its own terminal outcome, and a mid-batch failure attributes to
exactly one service. When several services are acted on, one operation MUST be enqueued per service,
in the order they were chosen, serialized through the existing mutation gate. `brew services kill`
and `brew services stop --keep` MUST NOT be offered: the product names four verbs, and a third and
fourth "stop-ish" verb whose difference is registration is not something this surface asks a user to
reason about.

No service verb MUST require confirmation: none of the four is destructive, and the confirmation gate
owned by `package-mutation` stays restricted to uninstall and zap.

This capability MUST NOT offer a bulk affordance over a multi-service selection in this slice, and
MUST NOT add a service verb to the installed list's bulk-action vocabulary. Any future services
multi-select MUST be its own type over its own entity.

#### Scenario: Each verb produces its exact argv

- GIVEN the service `atuin`
- WHEN start, stop, restart and run operations are built for it
- THEN their argvs are exactly `services start atuin`, `services stop atuin`,
  `services restart atuin` and `services run atuin`

#### Scenario: No service argv ever contains --all

- GIVEN every service verb built for one service and for several services
- WHEN the generated argvs are enumerated
- THEN none contains `--all`
- AND none names more than one service

#### Scenario: kill and stop --keep are not offered

- WHEN the service verbs this capability exposes are enumerated
- THEN exactly start, stop, restart and run are present
- AND no `kill` verb and no `--keep` variant is present

#### Scenario: Acting on several services enqueues one operation each, in order

- GIVEN the services `atuin`, `postgresql` and `redis`, chosen in that order
- WHEN a stop is requested for all three
- THEN exactly three operations are enqueued with the argvs `services stop atuin`,
  `services stop postgresql` and `services stop redis`, in that order

#### Scenario: The installed list's bulk vocabulary is unchanged

- WHEN the installed list's bulk-action vocabulary is enumerated
- THEN it still contains exactly upgrade and uninstall
- AND it contains no service verb

### Requirement: Start-at-login and run-once are distinct, explicit controls

`brew services start` registers a service to launch at login or boot; `brew services run` does not.
That difference MUST be surfaced as two separately labelled, separately invoked actions. It MUST NOT
be modelled as one verb with a flag, and no default, implicit or hidden choice MUST decide whether an
action touches the user's login items. The label of each action MUST state which of the two it does.

#### Scenario: The two actions submit different commands

- GIVEN the service `atuin`
- WHEN the start-at-login action and the run-once action are each invoked
- THEN the first submits the argv `services start atuin` and the second submits `services run atuin`
- AND neither is derived from the other by adding or removing an argument

#### Scenario: Neither action is a hidden default

- WHEN the actions offered for a stopped service are enumerated
- THEN both the start-at-login action and the run-once action are present and separately invocable
- AND no single action is presented that would choose between them on the user's behalf

### Requirement: Outcome classification comes from output markers, never from the exit code alone

A service operation's outcome MUST be classified from the content of its output, not from its exit
status alone, because `brew services` exits 0 for both a state change and a no-op.

`start` on a service that is already running exits 0 and emits ``already started, use `brew services
restart`` with no `Successfully` line; it MUST be classified as an **already in the requested state**
result, distinct from a fresh start, and MUST NOT be reported as a failure. `stop` on a service that
is already stopped exits 0 and emits, on stderr, ``Warning: Service `X` is not started.``; it MUST be
classified the same way. A registered but dead service MUST NOT be treated as already started —
`brew` keys that branch on a live process id, so such a service takes the full start path and MUST be
classified from that path's own output.

An operation that exits non-zero, or whose output matches no known marker, MUST be classified as a
generic failure with its raw log preserved verbatim. An unmatched outcome MUST NEVER be classified as
a success.

Classification MUST be display-only: nothing extracted from brew's prose MUST ever reach an argv. The
command that runs is always this capability's own typed command.

#### Scenario: A cold start is classified as started

- GIVEN a start operation exiting 0 with the stdout line
  "==> Successfully started `atuin` (label: homebrew.mxcl.atuin)"
- WHEN it reaches its terminal outcome
- THEN it is classified as a successful start

#### Scenario: A start on an already-running service is classified from the marker

- GIVEN a start operation exiting **0** with the single stdout line
  "Service `atuin` already started, use `brew services restart atuin` to restart." and no
  "Successfully" line
- WHEN it reaches its terminal outcome
- THEN it is classified as already in the requested state, distinctly from a fresh start
- AND it is not reported as a failure, and the classification did not come from the exit status

#### Scenario: A stop on an already-stopped service is classified from its stderr warning

- GIVEN a stop operation exiting **0** whose only output is the stderr line
  "Warning: Service `atuin` is not started."
- WHEN it reaches its terminal outcome
- THEN it is classified as already in the requested state
- AND it is not reported as a failure

#### Scenario: An unmatched outcome is a generic failure, never a success

- GIVEN a service operation exiting non-zero with output matching no known marker, and separately one
  exiting 0 with output matching no known marker
- WHEN each reaches its terminal outcome
- THEN the non-zero one is reported as a generic failure with its raw log preserved verbatim
- AND neither is reported as a state change that did not happen

#### Scenario: Nothing parsed from brew's output reaches an argv

- GIVEN the classification surface for service outcomes
- WHEN every value it extracts from brew's output is traced
- THEN none of them is used to build, extend or modify any argv

### Requirement: A root-domain start warns without prompting and never reports a false success

Starting a service that declares it needs root MUST NOT prompt for a password, MUST NOT collect,
store or forward one, and MUST NOT escalate privileges — the rules owned by `package-mutation`, which
this capability inherits rather than re-implements. Standard input MUST be the null device, so no
prompt could be answered even if one appeared.

`brew` emits a **non-fatal** warning on this path and then attempts to install the service into the
user domain. A run that emits that warning and then reaches a successful terminal outcome MUST be
reported as a success, not as a privilege failure, and the warning MUST remain visible in the
operation's log.

If the user-domain bootstrap is rejected, the operation exits non-zero. Because the exact failure
signature is unprobed, such a run MUST be classified as a generic failure with its raw log preserved
verbatim, and MUST NEVER be classified as a success or as a state change that did not happen. The
capability MUST NOT retry it automatically.

#### Scenario: A non-fatal root warning on a successful run is still a success

- GIVEN a start operation whose stderr carries
  "Warning: `<name>` must be run as root to start at system startup!" and which then exits 0 with a
  success marker
- WHEN it reaches its terminal outcome
- THEN it is reported as a successful start
- AND the warning line is still readable in its log

#### Scenario: A rejected bootstrap is a generic failure with its log intact

- GIVEN a start operation that emits the root warning and then exits non-zero with output matching no
  known marker
- WHEN it reaches its terminal outcome
- THEN it is reported as a generic failure
- AND its output is readable verbatim, and it was not retried automatically

#### Scenario: No password surface is ever offered for a service verb

- GIVEN any service operation executed by the capability
- WHEN the process it spawns is observed
- THEN that process's standard input is the null device
- AND no password input surface was offered to the user

### Requirement: A service operation invalidates services state only

Every service operation MUST declare an invalidation scope covering the services list and **nothing
else**. It MUST NOT declare the installed set, and MUST NOT force an installed-inventory re-snapshot
at any terminal outcome — starting or stopping a service changes nothing in the installed set, so the
probe could not observe a difference.

Success, failure and cancellation MUST each force exactly one services refresh — never zero and never
two — so the list a user sees always reflects the state after the operation settled.

#### Scenario: A successful service verb refreshes services once and the inventory never

- GIVEN a service start that exits 0, and a fake process launcher recording every invocation
- WHEN it reaches its terminal outcome
- THEN exactly one `services list --json` refresh is forced
- AND no `brew info --installed --json=v2` invocation was recorded

#### Scenario: A failed or cancelled service verb still refreshes services once

- GIVEN a service restart that exits non-zero, and separately one that is cancelled while running
- WHEN each reaches its terminal outcome
- THEN exactly one services refresh is forced for each
- AND no inventory re-snapshot is forced for either

### Requirement: A service that stops on its own surfaces on the next poll

A service that exits or fails outside Cellar MUST be reflected by the services list at the next poll
while the surface is visible, showing that service's real status from brew.

The capability MUST NOT deliver a system notification for it, MUST NOT request notification
permission, and MUST NOT raise a badge or a blocking alert. A stale status MUST NOT be retained: once
a refresh reports a different status, the previous one MUST NOT continue to be displayed.

#### Scenario: A service that dies is shown as failed at the next poll

- GIVEN a visible services surface listing a service reported as `started`
- WHEN brew's next list payload reports that service as `error` and one poll interval elapses
- THEN the list reports that service as `error`
- AND the previously displayed `started` status is no longer shown

#### Scenario: No notification is requested or delivered for it

- GIVEN the same transition
- WHEN the surfaces the capability produces for it are enumerated
- THEN no system notification was requested or delivered, and no permission prompt was raised
- AND no badge and no blocking alert was presented

### Requirement: A second operation for the same service is refused while one is in flight

While an operation for a given service is pending or running, another operation for **that same
service** MUST NOT be submitted, so a double-invoked control cannot queue two contradictory
operations against one service.

The guard MUST be scoped to that service alone: an operation for a different service MUST NOT be
blocked by it. It MUST NOT deduplicate across the whole queue — `brew-execution` permits duplicate
submissions of the same command in general and distinguishes them by identity, and this narrower rule
MUST NOT be generalised into a global deduplication. The guard MUST be released at that operation's
terminal outcome, whether it succeeded, failed or was cancelled.

#### Scenario: A second operation for the same service is refused

- GIVEN a start operation for `atuin` that is pending or running
- WHEN a stop is requested for `atuin` before that operation reaches a terminal outcome
- THEN no second operation is enqueued and no process is spawned for it

#### Scenario: A different service is not blocked

- GIVEN a start operation for `atuin` that is running
- WHEN a start is requested for `postgresql`
- THEN that operation is enqueued normally

#### Scenario: The guard is released at the terminal outcome

- GIVEN a start operation for `atuin` that has reached a terminal outcome — once successful, once
  failed and once cancelled
- WHEN a stop is requested for `atuin` afterwards in each case
- THEN it is enqueued normally in all three

### Requirement: With brew absent or invalid, services are empty and read-only

When brew detection reports absent, invalid or a missing configured path, the services list MUST be
empty, MUST NOT attempt a probe, MUST NOT poll, MUST NOT throw or block, and MUST surface the same
read-only guidance the rest of the app surfaces rather than an error state. No service verb MUST be
built or spawned in that state, and its affordance MUST report itself unavailable rather than failing
at spawn time.

When brew later becomes available, the services list MUST populate and the verbs MUST become
available without restarting the app.

#### Scenario: Absent brew produces an empty services list with guidance

- GIVEN brew detection reports absent
- WHEN the services list is read
- THEN it is empty, nothing is thrown, and read-only guidance is available
- AND no brew process was spawned and no poll loop is running

#### Scenario: A service verb requested with brew absent spawns nothing

- GIVEN brew detection reports absent, and separately an invalid configured path
- WHEN each of the four service verbs is requested
- THEN no process is spawned and nothing is thrown in any case
- AND the affordance reports itself unavailable, with the rejection reason available as guidance

#### Scenario: Services populate when brew appears

- GIVEN an empty services list because detection reported absent
- WHEN detection transitions to a valid installation and a refresh runs
- THEN the list reports the services from the resulting payload
- AND a service verb requested afterwards is built and submitted normally

### Requirement: A service is its own entity and never enters the package projection

A service MUST be identified by its own identity, distinct from the `(kind, name)` package identity
used by the catalog and the inventory. The installed-package projection MUST NOT gain a service
field, a service kind or a service-derived value, and the catalog search index MUST NOT gain any
service predicate or service term.

A service whose name coincides with an installed formula's name MUST NOT be assumed to be that
formula, and the capability MUST NOT derive service state from the inventory or inventory state from
the services list. `brew` remains the single source of truth for both, read through their own probes.

#### Scenario: The installed projection declares no service field

- GIVEN the installed-package projection's declared fields
- WHEN they are enumerated
- THEN none of them is a service field, a service kind or a service-derived value

#### Scenario: The catalog query declares no service predicate

- GIVEN the catalog query's declared filter set
- WHEN it is enumerated
- THEN it contains no service predicate
- AND no service term was added to the search index

#### Scenario: A name collision does not join the two

- GIVEN an installed formula `atuin` and a service named `atuin`
- WHEN the service's status is read and the formula's installed record is read
- THEN each was answered from its own probe
- AND neither value was derived from the other

## Provenance

- Established by change `m3-services` (archived `2026-08-03`, PRD milestone **M3**, slice M3-1 —
  Service Management), ADDED-only delta — **12 requirements / 40 scenarios**, promoted from
  `openspec/changes/archive/2026-08-03-m3-services/m3-services/specs/service-management/spec.md`.
  This is the first main spec for the capability; nothing was modified, removed or renamed. This file
  adds the header, the `## Requirements` wrapper and this provenance section. **No archive
  reconciliation was needed** — the promoted text is byte-identical to the delta's requirement and
  scenario bodies.
- Binding inputs settled **before** the delta was written, stated in it as facts rather than open
  questions:
  - **Live probe, brew 6.0.14** (Engram `#7178`, gate U8 closed), **re-confirmed on brew 6.0.15-4-gd610afe**
    during apply: `brew services start` on an already-running service exits **0** with stdout
    ``Service `X` already started, use `brew services restart X` to restart.`` — no `Error:`, no
    `Successfully` line. `brew services stop` on an already-stopped service exits **0** with stderr
    ``Warning: Service `X` is not started.`` Exit code alone therefore cannot classify a service
    verb's outcome, which is why `MutationOutcome` gained a `.noChange` case that is neither a
    success nor a failure. brew keys the already-started branch on `pid?`, not on registration, so a
    **registered-but-dead** service takes the full reload path.
  - **Live probe** (gate U5 closed, source-derived): a root-domain start as a non-root user **never**
    invokes sudo and can never reach a password prompt. brew emits a non-fatal warning, then installs
    the plist into the **user** domain and attempts a `launchctl bootstrap` that exits non-zero if
    rejected. The exact rejection signature is **unprobed** and is carried as an open follow-up; the
    classifier degrades to a generic failure with the log verbatim, which is a message-quality gap
    rather than a correctness gap.
  - **Status vocabulary, verified from Homebrew source** (`services/formula_wrapper.rb`,
    `status_symbol`): exactly seven values — `started`, `none`, `scheduled`, `stopped`, `error`,
    `unknown`, `other`. Only `none` is observable on the development machine, so fixtures are the
    primary evidence for the other six, corroborated by the pure status→label projection in
    `ServicesPresentationTests`.
  - **Product rulings** (user-confirmed 2026-08-03, Engram `#7180` and `#7182`): poll every 5 seconds
    while visible and never while hidden; all four verbs ship, with `start` (start at login) and
    `run` (run once) as explicitly distinct, visible controls; a service that dies on its own
    surfaces as a failed status on the next poll tick, with no notification and no badge.
  - **Live discriminator, obtained during apply**: `brew services run` does **not** write
    `~/Library/LaunchAgents/homebrew.mxcl.<name>.plist`; `brew services start` from a **stopped**
    service does. `start` on an *already running* service takes the already-started branch and does
    not register it — so the start/run distinction is only observable from a stopped service.
- **`package-mutation` owns the spine, this capability owns the vocabulary.** Serialized submission,
  the non-interactive stdin rule, the typed sudo and busy failures, the brew-absent rule and the
  invalidation-scope declaration are referenced, never restated, so a future change cannot fork a
  second execution or classification policy under this capability's name. `ServiceCommand` enters the
  spine through the shared `BrewMutating` abstraction, **not** as a seventh case of
  `MutationCommand` — which is what keeps `package-mutation`'s "exactly six" literally true.
- **The stdout widening is family-owned and deliberately contained.** `MutationOutcome`'s shipped
  marker rule is stderr-only, precisely so a package's build script cannot change what the user is
  told. Service classification must read **stdout** because that is where brew's already-started
  marker lands. The containment is structural rather than conventional: `ServiceCommand` overrides
  `classify` and the protocol default is untouched, so the widening cannot reach install or upgrade.
  Pinned by `packageClassificationIsByteIdentical` and
  `aPayloadContainingAServiceMarkerCannotReclassifyAnInstall`, and re-proved independently by
  mutation at verify.
- **`--all` is unrepresentable rather than merely forbidden.** No `ServiceCommand` case omits a
  target, so the type system — not a test and not a review — is what prevents a fan-out argv. This is
  the structural answer to the `upgradeAll` trap.
- **No services multi-select ships.** `installed-inventory` II13's "Only upgrade and uninstall are
  offered for a selection" is proven exhaustively over `BulkSelection.Action.allCases`; SM4 carries a
  guard scenario asserting the same fact from the services side, so the two capabilities cannot drift
  and a future services multi-select must be its own type over its own entity.
- **Verification note on the UI-only scenarios**: the app target has no automated coverage (follow-up
  **VS3**), so the services list, row, detail pane and controls are evidenced by twelve manual checks
  written **before** apply. MV-1 (the surface lists real state) and MV-7 (history records the verbs
  with no package identity, and no null-package entry is titled "All packages") were run in the built
  app on 2026-08-03 and both PASS; MV-3, MV-4, MV-5 and MV-11 were obtained in part. The remainder is
  deferred by an explicit user decision and registered as owed in the M3-1 archive report.
- **Amended by change `m12-menu-bar`** (archived `2026-08-26` —
  `openspec/changes/archive/2026-08-26-m12-menu-bar/`), **1 MODIFIED (SM3, *"The services surface polls
  only while visible, on an injected clock"*), 0 added, 0 removed, 0 renamed** — **12 req / 40 sc → 12
  req / 41 sc**. `rules.archive`'s destructive-delta warning did not fire: the replacement block is a
  **strict superset** of the shipped one. Verified mechanically at archive — the only two differences
  between the shipped block and the promoted block are the new secondary-surface paragraph with its
  `(Previously: …)` note and the new scenario; **every other line, including all four shipped scenarios,
  is byte-identical**, and those scenarios still carry no `- Verification:` line, exactly as before. The
  promoted block is byte-identical to
  `openspec/changes/archive/2026-08-26-m12-menu-bar/specs/service-management/spec.md:40-108` (empty
  diff), and SM1–SM2 and SM4–SM12 plus the whole prior `## Provenance` section were proven untouched by
  byte-slicing against a pre-merge copy. Archived on branch `feat/m12-menu-bar` at `270f41e`; **no PR
  was open and nothing was merged** when this amendment was promoted.
  - **What was missing.** The requirement described visibility solely as the services *section's* own —
    one refresh on becoming visible, then a 5-second cadence — and named exactly two reasons a surface
    stops being visible. A read-only surface that shows services state **without being that section**
    (the menu-bar popover) had no described home. Its only options were to overload the shared
    visibility boolean, leaving the poll running past the section's own disappearance, or to show
    nothing current at all.
  - **The gating conjunction is unchanged, and that is the point.** `isVisible = isSectionVisible &&
    isAppActive` keeps exactly the two halves it had. A secondary surface reports no visibility, so it
    can neither start a poll nor keep one alive; it performs exactly one baseline refresh on appearance
    and schedules nothing on the injected clock.
  - **Its one refresh is skipped, not deferred.** While a service mutation is in flight the baseline
    refresh does not run **and is not queued** for the mutation's terminal outcome — that outcome already
    owes exactly one refresh under *"A service operation invalidates services state only"*, and
    duplicating it is what the poll-suppression paragraph has always existed to prevent.
  - **The consumer is `menu-bar`**, whose MB5 honours this clause without restating the poll contract.
    The popover's own service controls reuse the shipped `ServiceRowControl` labels byte-for-byte, so one
    verb cannot read differently in the popover and in the Services section.
  - **`cellar/Services/ServicesListView.swift` is a 0-line diff** across the whole change: the compact
    control set arrived as a **defaulted** parameter, so the shipped list's call sites did not move.
  - The archived delta spec is the verbatim audit trail.
