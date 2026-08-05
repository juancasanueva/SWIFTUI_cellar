# Delta for tap-management

## ADDED Requirements

<!-- TM1 -->
### Requirement: One structured snapshot supplies tap list and detail

Each tap refresh MUST run exactly one `brew tap-info --installed --json` invocation. Its successful
array envelope MUST supply both the tap list and every selected tap's detail; the capability MUST NOT
run textual `brew tap` or another detail probe to complete that refresh. Cancellation, non-zero exit,
blank stdout, and a malformed non-array envelope MUST remain distinct user-visible outcomes.

#### Scenario: List and detail share one snapshot

- GIVEN a valid payload containing several taps
- WHEN the list is refreshed and each tap is selected
- THEN exactly one invocation ran with arguments `tap-info --installed --json`
- AND every detail came from that snapshot

#### Scenario: Acquisition failures are distinct

- GIVEN in turn a cancellation, non-zero exit, blank stdout, malformed JSON, and a valid non-array JSON envelope
- WHEN each refresh settles
- THEN each reports its corresponding user-visible outcome rather than an empty tap state
- AND no second brew invocation runs

<!-- TM2 -->
### Requirement: Tap decoding is tolerant, kind-aware, and safe for sensitive fields

Unknown keys MUST be ignored. An individually malformed record MUST be skipped without losing other
decodable records, while an envelope failure MUST fail the snapshot. `repo` MUST take precedence when
both `repo` and `repository` are present; `repository` MUST be the fallback only when `repo` is absent
or null. Qualified `formula_names` and `cask_tokens` MUST remain distinct typed inventories.
`last_commit` MUST be preserved as optional prose and MUST NOT be parsed as a date.

Any displayed remote URL MUST redact user information, including credentials. Raw tap payloads and
unredacted remotes MUST NOT be persisted.

#### Scenario: Added keys and one bad record preserve valid taps

- GIVEN an array with unknown keys, two valid records, and one undecodable record
- WHEN it is decoded
- THEN both valid taps are available and the bad record is skipped
- AND the snapshot succeeds

#### Scenario: Repo wins over its alias

- GIVEN a record with `repo: "primary"` and `repository: "other"`, and another with only `repository: "fallback"`
- WHEN both decode
- THEN their repositories are `primary` and `fallback`, respectively

#### Scenario: Prose commit data is not treated as a date

- GIVEN `last_commit` is `3 weeks ago`
- WHEN the detail is read
- THEN that exact prose is available without a synthesized date

#### Scenario: Credentials never survive presentation or persistence

- GIVEN a remote `https://alice:secret@example.com/acme/tools`
- WHEN the tap is presented and durable app data is inspected
- THEN neither `alice:secret` nor an equivalent credential appears
- AND no raw tap payload or unredacted URL was persisted

<!-- TM3 -->
### Requirement: Refreshes retain the last good snapshot and adopt only current work

A failed or cancelled refresh MUST retain the last successfully adopted snapshot while exposing the
new outcome. Concurrent identical requests MUST share one acquisition. A request after settlement
MUST acquire a fresh snapshot. An invalidation arriving during acquisition MUST make that acquisition
insufficient for freshness and MUST cause a later acquisition. If acquisitions settle out of order,
only the newest requested result MUST be adopted.

#### Scenario: Failure retains last-good data

- GIVEN snapshot `P1` is visible
- WHEN a refresh fails, is cancelled, or receives a malformed envelope
- THEN `P1` remains visible with the new error or cancellation state

#### Scenario: Identical overlapping requests are single-flight

- GIVEN one refresh is in flight for the same brew installation and invalidation mark
- WHEN another refresh is requested before it settles
- THEN one invocation serves both callers

#### Scenario: Newer work wins

- GIVEN acquisition `P1` is in flight
- WHEN invalidation requests `P2`, and `P2` settles before `P1`
- THEN a second invocation ran and only `P2` is adopted
- AND late `P1` cannot replace it

<!-- TM4 -->
### Requirement: Official sources are explanatory and only third-party taps are mutable

The capability MUST present non-actionable **Homebrew Core** and **Homebrew Cask** rows under
**Official sources**, each with the exact explanation “API-backed; no local tap required”. Those rows
MUST NOT expose tap or untap controls. Only third-party taps MUST expose mutation controls.

#### Scenario: Official sources are not installed-tap actions

- GIVEN a snapshot with or without local Core or Cask records
- WHEN sources are presented
- THEN Homebrew Core and Homebrew Cask each appear once with the exact API-backed explanation
- AND neither row offers tap or untap

#### Scenario: Zero third-party taps is useful, not erroneous

- GIVEN no third-party tap records decode
- WHEN the sources are presented
- THEN both official rows and the add action remain available
- AND the third-party section reports an empty state, not an error

<!-- TM5 -->
### Requirement: Tap package inventory preserves identity without entering the catalog

Every tap package MUST retain formula-or-cask kind as part of its identity. For a selected tap, a
formula display name MAY remove only the exact `<selected-tap>/` prefix; no other prefix or substring
MAY be removed, and cask tokens MUST retain their published token. Formula and cask entries with the
same token MUST remain distinct.

Installed status MUST come only from a complete installed snapshot whose exact `InstalledPackage.tap`
equals the selected tap, preserving package kind. An installed match MUST offer **Show in Installed**.
An uninstalled name MUST remain informational and show the exact copy “Not in Cellar’s core/cask
catalog.” Tap packages MUST NOT enter the catalog snapshot, catalog search, or catalog detail; PD6
remains unchanged and selection MUST NOT create a third-party detail fallback.

The inventory MUST be filterable by package name and kind. A large inventory MUST remain usable by
presenting only the filtered/visible rows needed at a time rather than requiring every row to be
presented eagerly.

#### Scenario: Only the selected tap prefix is normalized

- GIVEN selected tap `acme/tools` publishes formulae `acme/tools/widget` and `other/tap/widget`
- WHEN their display names are projected
- THEN they are `widget` and `other/tap/widget`, respectively

#### Scenario: Equal formula and cask tokens remain distinct

- GIVEN a formula and cask both displayed as `widget`
- WHEN inventory identities and kind filtering are inspected
- THEN two entries remain, one formula and one cask

#### Scenario: Exact installed tap controls the handoff

- GIVEN formula `widget` has installed tap `acme/tools`, while same-named cask has `other/tools`
- WHEN `acme/tools` inventory is presented
- THEN only the formula offers **Show in Installed**
- AND the cask shows “Not in Cellar’s core/cask catalog.”

#### Scenario: Tap names never become catalog records

- GIVEN an uninstalled package published only by a third-party tap
- WHEN catalog snapshot, search, and detail lookup are queried
- THEN it is absent from snapshot and search and detail returns ordinary not-found

#### Scenario: Large inventory can be narrowed without eager presentation

- GIVEN a tap containing thousands of formulae and casks
- WHEN a name-and-kind filter matches three casks
- THEN exactly those three results are presented as the visible result set
- AND presenting them does not require every non-matching row to be presented first

<!-- TM6 -->
### Requirement: Add accepts only a canonical tap target and always confirms typed argv

An add target MUST contain exactly two slash-separated components matching
`[A-Za-z0-9][A-Za-z0-9._-]*`. Empty components, leading-dash components, whitespace, extra path
components, URL schemes, scp-style remotes, and arbitrary custom/private remote values MUST be
rejected. Rejection MUST build and spawn no process.

For accepted `user/repo`, argv MUST be exactly `tap user/repo`. Every add MUST require confirmation
that names the tap, shows exactly `brew tap user/repo`, and warns that third-party taps can distribute
code through formulae and casks. The confirmed command MUST come from the validated typed request;
display or warning text MUST never be parsed into argv. Declining MUST submit nothing.

#### Scenario: Canonical target produces exact argv

- GIVEN accepted target `acme/tools`
- WHEN add is requested and confirmed
- THEN the displayed command is `brew tap acme/tools`
- AND spawned arguments are exactly `tap acme/tools`

#### Scenario: Hostile and unsupported targets are rejected

- GIVEN in turn ``, ` acme/tools`, `acme /tools`, `-acme/tools`, `acme/-tools`, `acme/tools/extra`, `https://example.com/a.git`, and `git@example.com:a.git`
- WHEN add is requested
- THEN each request is rejected and no confirmation, queue item, or process is created

#### Scenario: Every add discloses third-party code risk

- GIVEN any valid tap target, including one added previously
- WHEN add is requested
- THEN confirmation names the target and exact command and warns about third-party formula/cask code

#### Scenario: Presentation cannot rewrite execution

- GIVEN warning or display text containing command-like punctuation
- WHEN the typed add request is confirmed
- THEN spawned argv remains exactly the validated request's argv

<!-- TM7 -->
### Requirement: Plain untap is primary and force availability is fail-closed

For a third-party tap, ordinary removal MUST be the primary action and its argv MUST be exactly
`untap user/repo`; it MUST NOT require confirmation and MUST NOT silently retry with or append
`--force`. A complete, current installed
cross-reference containing zero exact matches MUST expose no force action. When installed inventory is
unavailable, stale, failed, or incomplete, force MUST be non-invocable with state guidance rather than
guessing. An enabled force action MUST appear only for a complete, current, non-empty cross-reference.

#### Scenario: Plain untap never grows a hidden force flag

- GIVEN third-party tap `acme/tools`
- WHEN ordinary untap is requested
- THEN spawned arguments are exactly `untap acme/tools`
- AND no implicit retry or `--force` argument occurs

#### Scenario: Empty current cross-reference hides force

- GIVEN a complete current installed snapshot with no exact `acme/tools` match
- WHEN actions are read
- THEN plain untap is primary and no force action is present

#### Scenario: Untrustworthy inventory cannot enable force

- GIVEN installed inventory is in turn unavailable, stale, failed, and incomplete
- WHEN actions are read and force is attempted
- THEN force is disabled with guidance in every case and no process is spawned

<!-- TM8 -->
### Requirement: Force untap discloses a current complete affected set

Force argv MUST be exactly `untap --force user/repo` and MUST require a separate confirmation. The
confirmation MUST name every affected installed package individually with formula-or-cask kind. It
MUST NOT elide entries or substitute only a count, even for a large set.

Immediately before spawn, the affected set MUST be compared with a complete current exact-tap
cross-reference using order-insensitive `(kind, name)` identity. Any addition, removal, or kind change
while confirmation is open or queued MUST invalidate the request before spawn, refresh the affected
set, and require a new confirmation. Reordering the same identities MUST NOT invalidate it.

#### Scenario: Disclosure names every kind-qualified package

- GIVEN a tap affects formula `widget`, cask `widget`, and formula `helper`
- WHEN force confirmation is presented
- THEN all three are named individually with their kinds and none is elided
- AND the exact command is `brew untap --force user/repo`

#### Scenario: Additions and removals invalidate stale confirmation

- GIVEN force confirmation is open or queued for affected set `{formula:a, cask:b}`
- WHEN the current set becomes `{formula:a, formula:c}`, once by removal and once by addition
- THEN no process spawns, the set refreshes, and fresh confirmation is required

#### Scenario: A kind change invalidates stale confirmation

- GIVEN force confirmation names `formula:widget`
- WHEN the current exact match becomes `cask:widget` before spawn
- THEN no process spawns and fresh confirmation names `cask:widget`

#### Scenario: Ordering alone does not invalidate confirmation

- GIVEN the confirmed and current sets contain identical `(kind, name)` identities in different orders
- WHEN the request reaches the front of the queue
- THEN it may spawn once with arguments `untap --force user/repo`

<!-- TM9 -->
### Requirement: Tap mutations use the shared mutation spine and scoped terminal invalidation

Tap add, plain untap, and force untap MUST inherit FIFO serialization, activity identity, exact
copy-command, live logs, cancellation, typed outcomes, and terminal recording from `brew-execution`,
`operation-activity`, `package-mutation`, and `installation-history`; this capability MUST NOT define
a second queue or execution policy.

Every terminal outcome, including launch failure and cancellation before spawn, MUST invalidate taps
exactly once for all three commands. Force untap MUST additionally invalidate installed inventory
exactly once. Tap add and plain untap MUST NOT invalidate installed inventory. No tap mutation MUST
invalidate or refresh the catalog.

#### Scenario: Tap mutations serialize with other mutations

- GIVEN a package mutation is running and tap add then plain untap are submitted
- WHEN operations settle
- THEN the tap operations run FIFO after it and receive ordinary activity, copy, log, cancel, and outcome projections

#### Scenario: Tap terminals refresh only declared domains

- GIVEN each tap command reaches success, failure, launch failure, and cancellation in turn
- WHEN terminal refreshes are counted
- THEN each terminal refreshes taps exactly once
- AND only force also refreshes installed inventory exactly once, while none refreshes catalog

<!-- TM10 -->
### Requirement: Availability, empty state, error state, and refresh guidance stay distinct

When brew detection reports absent, invalid, or a missing configured path, tap data MUST be empty,
the read-only guidance owned by `brew-detection` MUST be exposed, and no tap probe or mutation process
MUST spawn. When brew becomes valid, refresh and mutations MUST become available without restart.

A successful snapshot with no third-party taps MUST render the empty state defined by TM4. An
acquisition or decoding failure MUST render a user-visible error, never that empty state; refresh MUST
remain available when brew is valid and MUST obey TM3 freshness and last-good rules.

#### Scenario: Brew absence is guidance and spawns nothing

- GIVEN detection reports absent, invalid, or configured-path-missing
- WHEN tap data, refresh, add, and untap are requested
- THEN guidance is available and no process is spawned

#### Scenario: Valid brew restores the capability

- GIVEN taps are unavailable because brew was absent
- WHEN detection becomes valid and refresh succeeds
- THEN tap data populates and valid mutations become requestable without app restart

#### Scenario: Failure is not an empty third-party state

- GIVEN no last-good snapshot and a refresh fails
- WHEN state is presented
- THEN a user-visible error and refresh action are available
- AND the zero-third-party empty message is not shown

<!-- TM11 -->
### Requirement: Tap management does not expand into adjacent product capabilities

The capability MUST NOT offer Brewfile import/export, package installation from tap inventory,
third-party catalog ingestion or search, official-source cloning, tap security scanning, arbitrary Git
management, cleanup, disk usage, or service behavior. It MUST NOT create receipt-driven behavior.

#### Scenario: Enumerated tap actions stay within scope

- GIVEN the tap-management capability is available
- WHEN all actions exposed by tap management are enumerated
- THEN they are refresh, filter, Installed handoff, canonical add, plain untap, and eligible force untap
- AND none performs an excluded adjacent capability
