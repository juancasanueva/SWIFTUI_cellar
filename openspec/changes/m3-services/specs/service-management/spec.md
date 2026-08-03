# Delta for service-management

New capability — there is no `openspec/specs/service-management/spec.md` yet. Delta summary:
**12 ADDED requirements / 40 scenarios**. Nothing is MODIFIED, REMOVED or RENAMED.

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

Binding inputs settled **before** this delta was written, stated below as facts rather than open
questions:

- **Live probe, brew 6.0.14** (Engram `#7178`, gate U8 closed): `brew services start` on an
  already-running service exits **0** with stdout ``Service `X` already started, use `brew services
  restart X` to restart.`` — no `Error:`, no `Successfully` line. `brew services stop` on an
  already-stopped service exits **0** with stderr ``Warning: Service `X` is not started.`` Exit code
  alone therefore cannot classify a service verb's outcome. brew keys the already-started branch on
  `pid?`, not on registration, so a **registered-but-dead** service takes the full reload path.
- **Live probe** (gate U5 closed, source-derived): a root-domain start as a non-root user **never**
  invokes sudo and can never reach a password prompt. brew emits a non-fatal warning, then installs
  the plist into the **user** domain and attempts a `launchctl bootstrap` that exits non-zero if
  rejected. The exact failure signature is **unprobed** — see SM7.
- **Status vocabulary, verified from Homebrew source** (`services/formula_wrapper.rb`,
  `status_symbol`): exactly seven values — `started`, `none`, `scheduled`, `stopped`, `error`,
  `unknown`, `other`. Only `none` is observable on the development machine, so fixtures are the
  primary evidence for the other six.
- **Product rulings** (user-confirmed 2026-08-03, Engram `#7180` and `#7182`): poll every 5 seconds
  while visible and never while hidden; all four verbs ship, with `start` (start at login) and `run`
  (run once) as explicitly distinct, visible controls; a service that dies on its own surfaces as a
  failed status on the next poll tick, with no notification and no badge.

## ADDED Requirements

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
