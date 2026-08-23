# Delta for tap-management

Existing capability — `openspec/specs/tap-management/spec.md` (**11 requirements / 34 scenarios**,
established by the archived `2026-08-05-m3-taps`). This delta is **6 MODIFIED / 2 ADDED, 0 removed,
0 renamed**: **29 scenarios** replace the 20 the six modified blocks carry today, and **11 scenarios**
are added, taking the capability to **13 requirements / 54 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. Every MODIFIED block below is a whole-block replacement copied from the main spec and then
edited; each is a strict superset of the text it replaces.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m7-tap-trust/` + Engram canonical project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**Binding decisions consumed** (proposal, maintainer 2026-08-23): **D1** keeps Homebrew's tap/trust
split — add grants nothing, trust and untrust are separate explicitly answered commands, untap revokes
first, and a fully-qualified-argv bypass is prohibited; **D2** renames
`ConfirmationDisclosure.tapTrust` → `.tapAdd(TapName)` and adds `.tapTrustGrant(TapName)`. All five of
the proposal's open questions resolve to their stated defaults.

**Deviation from the proposal's requirement count, stated plainly.** The proposal budgets
`tap-management` at *one* ADDED requirement (TM12). This delta writes **two** — TM12 (the state is read
and shown) and TM13 (the grant is answered explicitly). One block covering both would have to specify
decoding, projection, argv, confirmation and invalidation at once, and its scenarios could not be read
as one testable subject. No rule is added or dropped by the split: TM12 + TM13 together carry exactly
the behaviour the proposal's TM12 row describes.

## Verification classes — with the runner named per class

Every scenario below declares exactly one verification class.

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` ("observable behavior of CellarCore types without referencing SwiftUI views") | `swift test --package-path Packages/CellarCore` by default; `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` for the app-target composition scenarios, which raise a confirmation from a view model | **38** |
| `manual-evidence` | no harness can exist — a real grant is written to `~/.homebrew/trust.json` by a real `brew` and observed there | the maintainer, on a real Mac running Homebrew 6.0.18; transcript captured in the verify report. **Binding: never run `brew upgrade` without `--dry-run` on that Mac** | **2** |

What stays **design-owned and is deliberately absent here**: view hierarchy and control placement,
the badge's rendered styling, which type holds the projection, the classifier's literal match strings,
and the wording of any log or activity label that is not pinned below as exact copy.

## MODIFIED Requirements

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

### Requirement: Plain untap is primary and force availability is fail-closed

For a third-party tap, ordinary removal MUST be the primary action. The removal action MUST submit
**two ordered commands**: the revocation `untrust user/repo` first, then the removal `untap user/repo`.
Each argv MUST be exactly those tokens and nothing else; the removal MUST NOT silently retry with or
append `--force`, and neither command MUST require confirmation, because revocation only *reduces*
authority.

The order is load-bearing and unconditional: revocation MUST run while the tap still resolves, and it
MUST be submitted even when the tap's trust state is `untrusted` or `unreported`, because `brew
untrust` on a never-trusted tap is an ordinary success. Untapping without revoking would leave a
dormant grant that Cellar can no longer see and that a later re-tap — including one performed by a
Brewfile import — would silently re-arm without new consent.

A failed revocation MUST NOT block the removal. The removal MUST still be submitted, and the failed
revocation MUST appear as its own visible operation with its own terminal outcome rather than being
swallowed, because the user's primary intent is removal and blocking it would leave them unable to
remove the tap at all.

A complete, current installed cross-reference containing zero exact matches MUST expose no force
action. When installed inventory is unavailable, stale, failed, or incomplete, force MUST be
non-invocable with state guidance rather than guessing. An enabled force action MUST appear only for a
complete, current, non-empty cross-reference.
(Previously: ordinary removal submitted the single command `untap user/repo`, so the trust grant
survived the tap it belonged to.)

#### Scenario: Plain untap never grows a hidden force flag

- GIVEN third-party tap `acme/tools`
- WHEN ordinary untap is requested
- THEN the removal command's spawned arguments are exactly `untap acme/tools`
- AND no implicit retry or `--force` argument occurs
- AND no confirmation is required
- Verification: `unit`

#### Scenario: Untap revokes before it removes

- GIVEN third-party tap `acme/tools`, in turn with trust state `trusted`, `untrusted` and `unreported`
- WHEN ordinary untap is requested
- THEN exactly two commands are submitted in every case, with argvs `untrust acme/tools` then `untap acme/tools`, in that order
- AND no third command is submitted
- Verification: `unit`

#### Scenario: A failed revocation does not block the removal

- GIVEN an untap action whose revocation command reaches a failed terminal outcome
- WHEN the action settles
- THEN the removal command was still submitted and reached its own terminal outcome
- AND the failed revocation is visible as its own operation rather than being suppressed
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

### Requirement: Force untap discloses a current complete affected set

The force removal action MUST submit the same two ordered commands as ordinary removal, with the
force removal in place of the plain one: the revocation `untrust user/repo` first, then
`untap --force user/repo`. The force removal's argv MUST be exactly those tokens and MUST require a
separate confirmation. The confirmation MUST name every affected installed package individually with
formula-or-cask kind. It MUST NOT elide entries or substitute only a count, even for a large set.

Prepending the revocation MUST NOT change which disclosure the confirmation presents. The revocation
declares no disclosure of its own, and `package-mutation` PM1 requires a batch to take the disclosure
of its first command that declares one, so the confirmation MUST still present the force-untap
affected-package disclosure and MUST NOT fall back to the ordinary package-removal disclosure.

Immediately before spawn, the affected set MUST be compared with a complete current exact-tap
cross-reference using order-insensitive `(kind, name)` identity. Any addition, removal, or kind change
while confirmation is open or queued MUST invalidate the request before spawn, refresh the affected
set, and require a new confirmation. Reordering the same identities MUST NOT invalidate it.
(Previously: force removal submitted the single command `untap --force user/repo`, so the trust grant
survived the tap it belonged to, and no rule protected the force disclosure from a leading command
that declares none.)

#### Scenario: Disclosure names every kind-qualified package

- GIVEN a tap affects formula `widget`, cask `widget`, and formula `helper`
- WHEN force confirmation is presented
- THEN all three are named individually with their kinds and none is elided
- AND the exact command is `brew untap --force user/repo`
- Verification: `unit`

#### Scenario: A revoke-first force batch still presents the force-untap disclosure

- GIVEN a force untap whose batch is `untrust user/repo` followed by `untap --force user/repo`
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the force-untap affected-package disclosure
- AND it is identical to the one the same force untap presents when submitted without the revocation
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

- GIVEN an untap action submitting `untrust acme/tools` then `untap acme/tools`
- WHEN both reach their terminal outcomes and refreshes are counted
- THEN installed inventory is refreshed exactly once, by the revocation
- AND the untap command's own declared domains still exclude installed inventory
- Verification: `unit`

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

## ADDED Requirements

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
two controls only: TM7's revocation before removal is unconditional, so untapping an `unreported` tap
MUST still submit `untrust`, where it MAY fail — on a Homebrew with no trust verb it always will — and
MUST remain visible as its own operation with its own terminal outcome rather than blocking the
removal or being suppressed. Only third-party taps MUST expose either control; TM4 keeps official
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
- AND neither control builds or spawns a process, and no trust command is submitted except the revocation TM7 pins ahead of that removal
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
after an explicit confirmed answer to a Trust request, or as the revocation TM7 and TM8 pin ahead of
removal. Revocation before removal is the one place a trust command is submitted without its own
answer, and it is permitted precisely because it grants nothing.

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

## Notes for archive

- The six MODIFIED blocks **replace** their same-named blocks in
  `openspec/specs/tap-management/spec.md` as whole blocks. TM1, TM2, TM3, TM4 and TM10 are untouched.
  The two ADDED blocks are appended after TM11.
- **TM2 needs no delta, verified.** It already requires that unknown keys be ignored, so a Homebrew
  that adds `trusted` was already tolerated; the new ADDED requirement owns the field.
- **TM10 needs no delta, verified against its text.** Its rule is command-agnostic — "no tap probe or
  mutation process MUST spawn" — and its scenario's list of requests is illustrative, not exhaustive.
  `package-mutation` PM7 already generalises the same rule to *every* command family on the shared
  spine. Nothing in TM10 reads on a count of three commands.
- **No `## Verification classes` table exists in this spec**, so — unlike the `m6-sparkle-updates` and
  `m6-cask-tap` precedent — there is **no class table to hand-update at archive**. This delta is the
  first to annotate `tap-management` scenarios with an inline `- Verification:` line, and the
  annotation is carried into the main spec with the promoted blocks. Untouched requirements keep no
  annotation; that asymmetry is deliberate and should be recorded rather than "fixed" by annotating
  blocks this change did not review.
- **Provenance arithmetic discrepancy, found while counting.** The main spec's provenance records
  `m3-taps` as **11 requirements / 33 scenarios**, but the file carries **34** `#### Scenario:`
  headings. Confirm by counting `#### Scenario:` lines rather than trusting either number, and correct
  the provenance entry in the same archive edit.
- Extend the provenance section with this change's binding decisions **D1** (keep Homebrew's tap/trust
  split; add grants nothing; trust and untrust are separate explicitly answered commands; untap revokes
  first; the fully-qualified-argv bypass is prohibited and asserted by test) and **D2** (rename
  `ConfirmationDisclosure.tapTrust` → `.tapAdd(TapName)`, add `.tapTrustGrant(TapName)`), each naming
  what was rejected: add-and-trust as one confirmed batch, the two-outcome confirmation, the pre-launch
  tap-state gate, and the fully-qualified argv.
- Record the **deviation** noted in this delta's header: the proposal budgeted one ADDED requirement
  and this delta writes two (TM12 and TM13). Resulting counts assume both.
- Record the deferred follow-ups so they are not re-derived: a per-package trust surface, a trust
  column in the Brewfile diff, and trust state for official taps (non-mutable under TM4, so no control
  could appear anyway).
