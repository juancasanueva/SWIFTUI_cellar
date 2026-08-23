# tap-management

Homebrew tap inventory, official-source framing, canonical add and safe untap workflows, package
cross-reference, freshness, typed confirmation disclosure, and scoped mutation invalidation. Owned by
`Packages/CellarCore` target `BrewClient` with app presentation in `cellar/Taps`.

## Requirements

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
formula display name and a cask display name MAY remove only the exact `<selected-tap>/` prefix; no
other prefix or substring MAY be removed. `brew tap-info --json` publishes cask tokens fully qualified
exactly as it publishes formula names, so the same rule applies to both kinds, and the projected
identity MUST be the bare token brew installs by; the published, fully qualified name MUST be retained
alongside it. Formula and cask entries with the same token MUST remain distinct.

Installed status MUST resolve into exactly **three typed states**, which MUST remain distinct values
and MUST NOT be collapsed into two:

1. **Installed** — a complete installed snapshot reports a package of the same kind whose exact
   `InstalledPackage.tap` equals the selected tap. It MUST offer **Show in Installed**.
2. **Installed, tap withheld** — the installed snapshot reports a package of the same kind and name
   whose `tap` is **absent** (Homebrew withholds the tap of a package it will not load), **and** the
   selected tap's trust state is `untrusted`, **and** the selected tap publishes this exact
   `(kind, name)`. It MUST show the exact copy “Installed. Homebrew withholds its tap while this tap is
   untrusted.” and it MUST still offer **Show in Installed**, because the handoff selects by exact
   `PackageID` and that identity is exact regardless of what brew withholds.
3. **Not installed** — every other case, including an absent `tap` under a tap whose trust state is
   `trusted` or `unreported`, and an absent `tap` for a `(kind, name)` the selected tap does not
   publish. It MUST show the exact copy “Not installed.” — a statement about this Mac, not about the
   catalog, because a third-party package is never in the catalog whether installed or not.

An absent tap MUST NOT be treated as equal to the selected tap, and MUST NOT be treated as equal to the
empty string; `installed-inventory` owns preserving that absence. The middle state's copy MUST be
scoped to the **tap** and MUST NOT state or imply that the package is untrusted, because a per-package
grant can make a package loadable while its tap is not trusted. Tap packages MUST NOT enter the catalog
snapshot, catalog search, or catalog detail; PD6 remains unchanged and selection MUST NOT create a
third-party detail fallback.

The inventory MUST be filterable by package name and kind. A large inventory MUST remain usable by
presenting only the filtered/visible rows needed at a time rather than requiring every row to be
presented eagerly.
(Previously: installed status came only from an exact `InstalledPackage.tap` equality, so a package
installed from an untrusted tap — whose tap brew withholds — was *mandated* to read “Not installed.”,
a false statement about this Mac.)

#### Scenario: Only the selected tap prefix is normalized

- GIVEN selected tap `acme/tools` publishes formulae `acme/tools/widget` and `other/tap/widget`
- WHEN their display names are projected
- THEN they are `widget` and `other/tap/widget`, respectively
- Verification: `unit`

#### Scenario: A fully qualified cask token matches the installed cask

- GIVEN selected tap `acme/tools` publishes cask token `acme/tools/widget`
- AND cask `widget` is installed from tap `acme/tools`
- WHEN the tap inventory is presented
- THEN the cask displays as `widget`, keeps `acme/tools/widget` as its published name, and offers **Show in Installed**
- Verification: `unit`

#### Scenario: Equal formula and cask tokens remain distinct

- GIVEN a formula and cask both displayed as `widget`
- WHEN inventory identities and kind filtering are inspected
- THEN two entries remain, one formula and one cask
- Verification: `unit`

#### Scenario: Exact installed tap controls the handoff

- GIVEN formula `widget` has installed tap `acme/tools`, while same-named cask has `other/tools`
- WHEN `acme/tools` inventory is presented
- THEN only the formula offers **Show in Installed**
- AND the cask shows “Not installed.”
- Verification: `unit`

#### Scenario: A withheld tap under an untrusted tap reads as installed, not as absent

- GIVEN selected tap `acme/tools` has trust state `untrusted` and publishes cask token `acme/tools/widget`
- AND the installed snapshot reports cask `widget` with no tap
- WHEN the tap inventory is presented
- THEN that cask reports the middle state with the exact copy “Installed. Homebrew withholds its tap while this tap is untrusted.”
- AND it still offers **Show in Installed**
- Verification: `unit`

#### Scenario: A withheld tap is not claimed by a tap that does not publish it

- GIVEN selected tap `acme/tools` has trust state `untrusted` and does not publish cask `stranger`
- AND the installed snapshot reports cask `stranger` with no tap
- WHEN the tap inventory is presented
- THEN `stranger` is absent from that tap's inventory and no middle-state claim is made for it
- Verification: `unit`

#### Scenario: A withheld tap under a trusted or unreported tap is still “Not installed.”

- GIVEN selected tap `acme/tools` in turn has trust state `trusted` and `unreported`, and publishes cask token `acme/tools/widget`
- AND the installed snapshot reports cask `widget` with no tap
- WHEN the tap inventory is presented
- THEN both cases show the exact copy “Not installed.”
- AND neither presents the withheld-tap copy
- Verification: `unit`

#### Scenario: Tap names never become catalog records

- GIVEN an uninstalled package published only by a third-party tap
- WHEN catalog snapshot, search, and detail lookup are queried
- THEN it is absent from snapshot and search and detail returns ordinary not-found
- Verification: `unit`

#### Scenario: Large inventory can be narrowed without eager presentation

- GIVEN a tap containing thousands of formulae and casks
- WHEN a name-and-kind filter matches three casks
- THEN exactly those three results are presented as the visible result set
- AND presenting them does not require every non-matching row to be presented first
- Verification: `unit`

<!-- TM6 -->
### Requirement: Add accepts only a canonical tap target and always confirms typed argv

An add target MUST contain exactly two slash-separated components matching
`[A-Za-z0-9][A-Za-z0-9._-]*`. Empty components, leading-dash components, whitespace, extra path
components, URL schemes, scp-style remotes, and arbitrary custom/private remote values MUST be
rejected. Rejection MUST build and spawn no process.

For accepted `user/repo`, argv MUST be exactly `tap user/repo`. Every add MUST require confirmation
that names the tap and shows exactly `brew tap user/repo`.

That confirmation's disclosure MUST state truthfully what adding does and what it does **not** do.
Adding a tap clones a third-party repository; on Homebrew 6 it grants no trust, so the disclosure MUST
NOT assert or imply that a capability was granted. Its exact text MUST be “Adding \(tap) clones a
third-party repository. Homebrew will not load its formulae or casks until you trust it, and Cellar
does not trust it for you.” Adding MUST NOT submit a trust command, MUST NOT change any tap's trust
state, and MUST NOT be paired with one implicitly on any path, including a Brewfile import.

The confirmed command MUST come from the validated typed request; display or warning text MUST never be
parsed into argv. Declining MUST submit nothing.
(Previously: every add warned that “third-party taps can distribute code through formulae and casks”,
wording that over-claimed a capability grant `brew tap` never makes — the tap it added was inert.)

#### Scenario: Canonical target produces exact argv

- GIVEN accepted target `acme/tools`
- WHEN add is requested and confirmed
- THEN the displayed command is `brew tap acme/tools`
- AND spawned arguments are exactly `tap acme/tools`
- Verification: `unit`

#### Scenario: Hostile and unsupported targets are rejected

- GIVEN in turn ``, ` acme/tools`, `acme /tools`, `-acme/tools`, `acme/-tools`, `acme/tools/extra`, `https://example.com/a.git`, and `git@example.com:a.git`
- WHEN add is requested
- THEN each request is rejected and no confirmation, queue item, or process is created
- Verification: `unit`

#### Scenario: Every add discloses what adding does and does not do

- GIVEN any valid tap target, including one added previously
- WHEN add is requested
- THEN confirmation names the target and the exact command
- AND its disclosure text is exactly “Adding acme/tools clones a third-party repository. Homebrew will not load its formulae or casks until you trust it, and Cellar does not trust it for you.”
- Verification: `unit`

#### Scenario: Adding a tap grants no trust

- GIVEN a confirmed add of `acme/tools`, and separately a confirmed Brewfile import naming that tap
- WHEN every command each submits is enumerated
- THEN neither submits a trust command
- AND the tap's trust state after the add is whatever the snapshot reports, unchanged by the add
- Verification: `unit`

#### Scenario: Presentation cannot rewrite execution

- GIVEN warning or display text containing command-like punctuation
- WHEN the typed add request is confirmed
- THEN spawned argv remains exactly the validated request's argv
- Verification: `unit`

<!-- TM7 -->
### Requirement: Plain untap is primary and force availability is fail-closed

For a third-party tap, ordinary removal MUST be the primary action. The removal action MUST submit
**two ordered commands**: the removal `untap user/repo` first, then the revocation `untrust user/repo`.
Each argv MUST be exactly those tokens and nothing else; the removal MUST NOT silently retry with or
append `--force`, and neither command MUST require confirmation, because revocation only *reduces*
authority.

The order is load-bearing (maintainer decision **D4**, 2026-08-23). Homebrew refuses to untap a tap
that still owns installed packages — `Refusing to untap user/repo because it contains the following
installed casks: …`, exit 1 — so a revocation submitted *before* such a removal succeeds while the
removal is refused. That leaves the grant revoked, the tap still installed, and Force Untap hidden
because it is offered only for a tap whose packages Homebrew will still name: a dead end whose only
signposted exit was the removal that had just failed.

The revocation MUST therefore be submitted **only after** the removal has settled with a successful
terminal outcome. A refused removal MUST submit no revocation at all: no queue item MUST appear for a
command that was never run, and the failed removal MUST carry Homebrew's own reason. The grant MUST
NOT outlive a *successful* removal; it MAY outlive a refused one, which is the only state that still
has a tap for it to belong to.

Behind a removal Homebrew accepted, the revocation MUST be unconditional. It MUST be submitted even
when the tap's trust state is `untrusted` or `unreported`, because `brew untrust` on a never-trusted
tap is an ordinary success. Removing without revoking would leave a dormant grant that Cellar can no
longer see and that a later re-tap — including one performed by a Brewfile import — would silently
re-arm without new consent.

A complete, current installed cross-reference containing zero exact matches MUST expose no force
action. When installed inventory is unavailable, stale, failed, or incomplete, force MUST be
non-invocable with state guidance rather than guessing. An enabled force action MUST appear only for a
complete, current, non-empty cross-reference.
(Previously: ordinary removal submitted the single command `untap user/repo`, so the trust grant
survived the tap it belonged to. Then, until D4 on 2026-08-23, it submitted the revocation first and
both commands unconditionally, so a removal Homebrew refused still lost the grant.)

#### Scenario: Plain untap never grows a hidden force flag

- GIVEN third-party tap `acme/tools`
- WHEN ordinary untap is requested
- THEN the removal command's spawned arguments are exactly `untap acme/tools`
- AND no implicit retry or `--force` argument occurs
- AND no confirmation is required
- Verification: `unit`

#### Scenario: Untap removes before it revokes

- GIVEN third-party tap `acme/tools`, in turn with trust state `trusted`, `untrusted` and `unreported`
- WHEN ordinary untap is requested
- THEN the action's two commands are, in every case, `untap acme/tools` then `untrust acme/tools`, in that order
- AND no third command is submitted
- Verification: `unit`

#### Scenario: A refused removal submits no revocation

- GIVEN an untap action whose removal command is refused by Homebrew with a failed terminal outcome
- WHEN the action settles
- THEN no revocation command was submitted, and no queue item exists for one
- AND the refused removal is visible as its own operation carrying Homebrew's reason
- Verification: `unit`

#### Scenario: A successful removal is followed by the idempotent revocation

- GIVEN an untap action whose removal command reaches a successful terminal outcome, for a tap in turn
  `trusted`, `untrusted` and `unreported`
- WHEN the removal settles
- THEN the revocation is submitted behind it, unconditionally, and reaches its own terminal outcome
- AND an exit 0 from `untrust` on a never-trusted tap is an ordinary success, not a failure
- Verification: `unit`

#### Scenario: Empty current cross-reference hides force

- GIVEN a complete current installed snapshot with no exact `acme/tools` match
- WHEN actions are read
- THEN plain untap is primary and no force action is present
- Verification: `unit`

#### Scenario: Untrustworthy inventory cannot enable force

- GIVEN installed inventory is in turn unavailable, stale, failed, and incomplete
- WHEN actions are read and force is attempted
- THEN force is disabled with guidance in every case and no process is spawned
- Verification: `unit`

<!-- TM8 -->
### Requirement: Force untap discloses a current complete affected set

The force removal action MUST submit the same two ordered commands as ordinary removal, with the
force removal in place of the plain one: `untap --force user/repo` first, then the revocation
`untrust user/repo` behind a successful removal (**D4**, 2026-08-23). The force removal's argv MUST be
exactly those tokens and MUST require a separate confirmation. The confirmation MUST name every
affected installed package individually with formula-or-cask kind. It MUST NOT elide entries or
substitute only a count, even for a large set.

The trailing revocation MUST NOT change which disclosure the confirmation presents. `package-mutation`
PM1 requires a batch to take the disclosure of its first command that declares one; the force removal
now leads and declares that disclosure directly, so the confirmation MUST present the force-untap
affected-package disclosure and MUST NOT fall back to the ordinary package-removal disclosure. The
lead-disclosure rule itself is unchanged and MUST continue to skip a leading command that declares
nothing.

Immediately before spawn, the affected set MUST be compared with a complete current exact-tap
cross-reference using order-insensitive `(kind, name)` identity. Any addition, removal, or kind change
while confirmation is open or queued MUST invalidate the request before spawn, refresh the affected
set, and require a new confirmation. Reordering the same identities MUST NOT invalidate it.
(Previously: force removal submitted the single command `untap --force user/repo`, so the trust grant
survived the tap it belonged to, and no rule protected the force disclosure from a leading command
that declares none. Then, until D4 on 2026-08-23, the revocation led the sequence unconditionally, so
a force removal Homebrew refused still lost the grant.)

#### Scenario: Disclosure names every kind-qualified package

- GIVEN a tap affects formula `widget`, cask `widget`, and formula `helper`
- WHEN force confirmation is presented
- THEN all three are named individually with their kinds and none is elided
- AND the exact command is `brew untap --force user/repo`
- Verification: `unit`

#### Scenario: A remove-first force batch still presents the force-untap disclosure

- GIVEN a force untap whose batch is `untap --force user/repo` followed by `untrust user/repo`
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the force-untap affected-package disclosure
- AND it is identical to the one the same force untap presents when submitted without the revocation
- AND a batch whose leading command declares no disclosure of its own is still skipped past
- Verification: `unit`

#### Scenario: Additions and removals invalidate stale confirmation

- GIVEN force confirmation is open or queued for affected set `{formula:a, cask:b}`
- WHEN the current set becomes `{formula:a, formula:c}`, once by removal and once by addition
- THEN no process spawns, the set refreshes, and fresh confirmation is required
- Verification: `unit`

#### Scenario: A kind change invalidates stale confirmation

- GIVEN force confirmation names `formula:widget`
- WHEN the current exact match becomes `cask:widget` before spawn
- THEN no process spawns and fresh confirmation names `cask:widget`
- Verification: `unit`

#### Scenario: Ordering alone does not invalidate confirmation

- GIVEN the confirmed and current sets contain identical `(kind, name)` identities in different orders
- WHEN the request reaches the front of the queue
- THEN it may spawn once with arguments `untap --force user/repo`
- Verification: `unit`

<!-- TM9 -->
### Requirement: Tap mutations use the shared mutation spine and scoped terminal invalidation

Tap add, plain untap, force untap, **trust and untrust** MUST inherit FIFO serialization, activity
identity, exact copy-command, live logs, cancellation, typed outcomes, and terminal recording from
`brew-execution`, `operation-activity`, `package-mutation`, and `installation-history`; this capability
MUST NOT define a second queue or execution policy.

Every terminal outcome, including launch failure and cancellation before spawn, MUST invalidate taps
exactly once for all five commands. Force untap, trust and untrust MUST additionally invalidate
installed inventory exactly once, because a trust change alters what the installed snapshot reports:
Homebrew withholds a package's tap while that tap is untrusted, so the inventory's own `tap` field
changes with the grant. Tap add and the plain untap command MUST NOT invalidate installed inventory.

Invalidation is declared **per command**, not per action. An untap action therefore refreshes installed
inventory exactly once by virtue of the revocation it submits, and never by widening what the untap
command itself declares. No tap mutation MUST invalidate or refresh the catalog.
(Previously: the requirement enumerated exactly three commands and stated that only force untap also
refreshes installed inventory — false once trust and untrust exist, because a trust change is exactly
what makes the inventory's `tap` field change.)

#### Scenario: Tap mutations serialize with other mutations

- GIVEN a package mutation is running and tap add then plain untap are submitted
- WHEN operations settle
- THEN the tap operations run FIFO after it and receive ordinary activity, copy, log, cancel, and outcome projections
- Verification: `unit`

#### Scenario: Tap terminals refresh only declared domains

- GIVEN each of the five tap commands reaches success, failure, launch failure, and cancellation in turn
- WHEN terminal refreshes are counted
- THEN each terminal refreshes taps exactly once
- AND force untap, trust and untrust each also refresh installed inventory exactly once, while tap add and plain untap refresh it zero times
- AND none refreshes catalog
- Verification: `unit`

#### Scenario: An untap action's inventory refresh comes from its revocation

- GIVEN an untap action submitting `untap acme/tools` then `untrust acme/tools`
- WHEN both reach their terminal outcomes and refreshes are counted
- THEN installed inventory is refreshed exactly once, by the revocation
- AND the untap command's own declared domains still exclude installed inventory
- Verification: `unit`

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

Showing a tap's trust state and offering to grant or revoke it is **not** tap security scanning: the
state is read from brew's own snapshot and the grant is brew's own command. The capability MUST NOT
inspect, analyse, score or judge a tap's contents, and MUST NOT derive a trust recommendation.
(Previously: the enumerated action set had six members and predated any trust surface.)

#### Scenario: Enumerated tap actions stay within scope

- GIVEN the tap-management capability is available
- WHEN all actions exposed by tap management are enumerated
- THEN they are refresh, filter, Installed handoff, canonical add, plain untap, eligible force untap, trust, and untrust
- AND none performs an excluded adjacent capability
- Verification: `unit`

#### Scenario: Trust is a reported state and a grant, never a verdict

- GIVEN the trust surface
- WHEN everything it presents about a tap is enumerated
- THEN each item is either the state brew reported or a control that submits brew's own grant or revocation
- AND nothing inspects, scores or recommends for or against a tap's contents
- Verification: `unit`

<!-- TM12 -->
### Requirement: Tap trust is read from the tap snapshot and shown as a three-valued state

A tap's trust state MUST be read from the snapshot this capability already acquires — the per-tap
`trusted` boolean carried by `brew tap-info --installed --json`. It MUST NOT require a second probe, a
second store, a second source of truth, or a new invalidation domain.

The state MUST be **three-valued** — `trusted`, `untrusted`, `unreported` — and MUST NOT be reduced to
a boolean. `unreported` is the absent or null field: a Homebrew with no trust concept. Absence MUST NOT
be read as `untrusted`, on exactly the terms `installed-inventory` already applies to a cask's
tri-state `auto_updates`: "not declared" is not "declared false".

Exactly one projection MUST supply the trust presentation consumed by both the tap list row and the tap
detail header, so the two cannot drift. An `untrusted` tap MUST carry the exact badge text “Untrusted”
and MUST offer the **Trust** control. A `trusted` tap MUST carry no badge and MUST offer the
**Untrust** control. An `unreported` tap MUST carry no badge and MUST offer **neither** control, and
neither the **Trust nor the Untrust control** MUST build or spawn a process for it. This governs the
two controls only: TM7's revocation behind a successful removal is unconditional, so untapping an
`unreported` tap MUST still submit `untrust` once Homebrew has accepted the removal, where it MAY fail
— on a Homebrew with no trust verb it always will — and MUST remain visible as its own operation with
its own terminal outcome rather than being suppressed. Only third-party taps MUST expose either control; TM4 keeps official
sources non-mutable.

Every user-facing string in this surface MUST be scoped to the **tap**. None MUST state or imply that a
package is untrusted, because a per-package grant is independent of a tap grant and can make a package
loadable while its tap is not trusted.

#### Scenario: Trust decodes into three distinct states

- GIVEN tap records whose `trusted` field is in turn `true`, `false`, `null`, and absent
- WHEN the snapshot is decoded
- THEN the states are `trusted`, `untrusted`, `unreported` and `unreported`, respectively
- AND no absent field is reported as `untrusted`
- Verification: `unit`

#### Scenario: An unreported tap's controls show nothing and spawn nothing

- GIVEN a tap whose snapshot record carries no `trusted` field
- WHEN it is projected, its controls are enumerated and invoked, and it is separately untapped
- THEN it carries no badge and offers neither Trust nor Untrust
- AND neither control builds or spawns a process, and no trust command is submitted except the revocation TM7 pins behind that removal once Homebrew accepts it
- Verification: `unit`

#### Scenario: The badge and controls follow the state exactly

- GIVEN one `untrusted` tap and one `trusted` tap
- WHEN each is projected
- THEN the first carries the exact badge text “Untrusted” and offers Trust but not Untrust
- AND the second carries no badge and offers Untrust but not Trust
- Verification: `unit`

#### Scenario: List row and detail header read one projection

- GIVEN a tap in each of the three states
- WHEN the trust presentation consumed by the list row and by the detail header is compared
- THEN both come from the same projection and are identical for every state
- Verification: `unit`

#### Scenario: Trust copy is about the tap, never about a package

- GIVEN every user-facing string this capability presents about trust
- WHEN they are enumerated
- THEN each is scoped to the tap
- AND none states or implies that a package is untrusted
- Verification: `unit`

<!-- TM13 -->
### Requirement: Trust is granted and revoked only by an explicit answer, and never implicitly

Trust MUST be representable as two typed commands whose argvs are exactly `trust user/repo` and
`untrust user/repo`. Both MUST be built from literal verbs and the validated typed tap identity; no
argv element MUST be interpolated, joined or split into existence. Neither MUST carry a package
identity, because trust is a property of a tap.

**Trust MUST be confirmed.** Granting trust lets Homebrew load and run third-party code as the user,
with the user's permissions, so every grant MUST require an explicit confirmation carrying the typed
grant disclosure whose exact text is “Trusting \(tap) lets Homebrew load and run its formulae and
casks. That is third-party code running as you, with your permissions.” Declining MUST submit nothing.

**Untrust MUST NOT be confirmed.** Revocation only reduces authority, so it MUST pass the shared gate
without a confirmation and MUST NOT be presented as a destructive action.

**No path MUST grant trust implicitly.** Adding a tap, importing a Brewfile, recovering from a refusal,
and retrying a failed mutation MUST each submit no trust command. A tap's trust state MUST change only
after an explicit confirmed answer to a Trust request, or as the revocation TM7 and TM8 pin behind a
removal Homebrew accepted. That trailing revocation is the one place a trust command is submitted
without its own answer, and it is permitted precisely because it grants nothing.

Both commands MUST declare taps and installed inventory as the domains they invalidate, per TM9. Both
are idempotent at brew: trusting an already-trusted tap and untrusting a never-trusted tap MUST be
reported as ordinary successful outcomes, not as errors and not as a Cellar defect.

#### Scenario: Trust and untrust produce exact argv

- GIVEN the third-party tap `acme/tools`
- WHEN trust and untrust commands are built for it
- THEN their argvs are exactly `trust acme/tools` and `untrust acme/tools`
- AND neither carries a package identity, a kind flag, or any additional token
- Verification: `unit`

#### Scenario: A grant is confirmed and a revocation is not

- GIVEN a trust request and an untrust request for `acme/tools`
- WHEN each reaches the shared confirmation gate
- THEN the trust request raises exactly one confirmation whose disclosure text is exactly “Trusting acme/tools lets Homebrew load and run its formulae and casks. That is third-party code running as you, with your permissions.”
- AND the untrust request raises none and is submitted directly
- AND declining the trust confirmation spawns no process and enqueues nothing
- Verification: `unit`

#### Scenario: No path grants trust implicitly

- GIVEN in turn a confirmed tap add, a confirmed Brewfile import naming a tap with a `trusted:` option, a recovery offered after an untrusted-tap refusal, and a retry of a failed mutation
- WHEN every command each submits is enumerated
- THEN none of them is a trust command
- AND the only submitted trust command in the capability follows an explicit confirmed Trust answer
- Verification: `unit`

#### Scenario: An idempotent grant or revocation is an ordinary success

- GIVEN a trust command for an already-trusted tap and an untrust command for a never-trusted tap
- WHEN each reaches its terminal outcome with exit status 0
- THEN each is reported as an ordinary success
- AND neither is reported as a failure or as a Cellar defect
- Verification: `unit`

#### Scenario: A real grant round trip flips the badge without a manual reload

- GIVEN a freshly added third-party tap on a Mac running Homebrew 6.0.18
- WHEN Cellar shows it as Untrusted and the maintainer answers Trust in the app
- THEN `brew trust --json v1` lists that tap
- AND the badge clears with no manual reload
- Verification: `manual-evidence`

#### Scenario: Untapping a trusted tap leaves no grant behind

- GIVEN a third-party tap that has been trusted, listed by `brew trust --json v1`
- WHEN it is untapped from inside Cellar
- THEN `brew trust --json v1` no longer lists it
- Verification: `manual-evidence`

## Provenance

- Established by change `m3-taps` (archived `2026-08-05`, PRD milestone **M3**, slice M3-2 — Tap
  Management), ADDED-only delta — **11 requirements / 34 scenarios**. The requirement and scenario
  bodies are promoted from `openspec/changes/archive/2026-08-05-m3-taps/specs/tap-management/spec.md`.
  *(Arithmetic corrected 2026-08-23 while archiving `m7-tap-trust`. This line read "11 requirements /
  **33** scenarios" from the day it was written, while the file has carried **34** `#### Scenario:`
  headings throughout. The 34 is the truth, recounted directly from the file rather than from either
  recorded number; the 33 was a transcription defect, not a lost scenario.)*

- Amended by change `m7-tap-trust` (archived `2026-08-23` —
  `openspec/changes/archive/2026-08-23-m7-tap-trust/`), **6 MODIFIED / 2 ADDED, 0 removed, 0 renamed**
  — **11 req / 34 sc → 13 req / 55 sc**. The six modified blocks carried 20 scenarios and were replaced
  by 30; TM12 and TM13 added 11. `rules.archive`'s destructive-delta warning did not fire: nothing was
  removed and nothing was renamed, and every requirement this delta did not name (TM1–TM4, TM10) is
  byte-identical to its prior text.
  - **Deviation from the proposal's requirement budget, recorded rather than smoothed over.** The
    proposal budgeted *one* ADDED requirement here (TM12). The delta wrote **two** — TM12 (the state is
    read and shown) and TM13 (the grant is answered explicitly) — because a single block would have had
    to specify decoding, projection, argv, confirmation and invalidation at once, and its scenarios
    could not be read as one testable subject. No rule was added or dropped by the split; the counts
    above assume both.
  - **D1** (maintainer, 2026-08-23) keeps Homebrew's tap/trust split: `brew tap` grants nothing, Trust
    and Untrust are separate explicitly answered commands, and a fully-qualified-argv bypass is
    prohibited and asserted by an absence test. **Rejected:** add-and-trust as one confirmed batch (it
    makes "fetch without granting execution authority" unrepresentable); a two-outcome confirmation (it
    needs a partial-confirm path contradicting `package-mutation` PM3); a pre-launch tap-state gate (a
    per-package grant makes such a gate block what brew itself allows — obs `#7724`); and qualified
    argv, because `trust.rb#explicitly_allowed?` treats naming the qualified package **as** the grant,
    which makes it the bypass dressed as a fix.
  - **D2** (maintainer, 2026-08-23) renames `ConfirmationDisclosure.tapTrust` → `.tapAdd(TapName)` and
    adds `.tapTrustGrant(TapName)`. **Rejected:** keeping one case named for a grant the add command
    never made.
  - **D4** (maintainer, 2026-08-23, taken *after* the first verification verdict) reverses the order D1
    originally fixed: the removal runs **first**, and the revocation is submitted only behind a removal
    Homebrew accepted. Found by Phase 9 manual evidence — brew refuses `untap` for a tap that still owns
    installed packages (exit 1), so a revocation submitted first succeeded while the removal was
    refused, leaving the user on an untrusted tap with Force Untap hidden: a dead end whose only
    signposted exit was the removal that had just failed. `brew untrust` after a successful `brew untap`
    was measured at exit 0. **Rejected:** submitting both commands unconditionally (exactly the state D4
    exists to remove), and suppressing the revocation's own failure. TM7 and TM8 carry the two-stage
    `(Previously:)` note that records both prior states, and TM7 gained the scenario *"A refused removal
    submits no revocation"* — the +1 that moved this capability from 54 to 55 scenarios.
  - **No `## Verification classes` table exists in this spec**, so none was hand-updated at archive.
    `m7-tap-trust` is the first change to annotate this capability's scenarios with an inline
    `- Verification:` line; the annotation travels with the promoted blocks, and the untouched
    requirements deliberately keep none. That asymmetry is recorded here rather than "fixed" by
    annotating blocks this change never reviewed.
  - **One archive-time correction inside a promoted block, recorded because it was not mechanical.**
    TM9's scenario *"An untap action's inventory refresh comes from its revocation"* still opened
    `GIVEN an untap action submitting untrust … then untap …` — the **pre-D4** order, contradicting
    TM7 above and the covering test, which asserts `["untap", …]` then `["untrust", …]`
    (`MutationRefreshReceiptTests · anUntapActionsInventoryRefreshComesFromItsRevocation`). The GIVEN
    clause was corrected to the D4 order in the archived delta first and promoted from it, so the
    archived delta and this spec remain byte-identical. No count changed and no rule moved.
  - Deferred follow-ups, recorded so they are not re-derived: a **per-package trust surface** — v1 shows
    tap-level state only, so a tap whose packages work through per-package grants still reads
    "Untrusted"; a trust column in the Brewfile diff; and trust state for official taps, which TM4 keeps
    non-mutable so no control could appear for them anyway.
