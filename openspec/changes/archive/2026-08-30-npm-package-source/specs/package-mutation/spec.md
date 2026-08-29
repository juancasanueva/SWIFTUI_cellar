# Delta for package-mutation

Existing capability — `openspec/specs/package-mutation/spec.md` (**10 requirements / 63 scenarios**).
This delta is **3 ADDED, 1 modified, 0 removed, 0 renamed**. PM7 ("No mutation is built or spawned
when brew is absent or invalid") is replaced as a whole block, a strict superset of its shipped text; the
other nine requirements are byte-identical. The capability becomes **13 requirements / 76 scenarios**.

PM1's "exactly six" stays literally true: the npm family enters through the shared abstraction exactly
as services and taps did.

## ADDED Requirements

### Requirement: Every spine command projects its source, and the erased form preserves it

The shared abstraction MUST expose a `source` projection — Homebrew or npm — defaulting to Homebrew
for every existing conformer. The display command and the copy-command text MUST derive their prefix
(`brew ` or `npm `) from that projection and from nothing else. The erased command type MUST copy
`source` exactly as it copies argv, verb and disclosure, so an erased npm command never renders,
copies or records as a brew command. No consumer MUST recover the source by downcast, type test or
verb-string inspection.

#### Scenario: Existing families default to Homebrew and npm declares npm

- GIVEN one package, one service, one tap and one npm command
- WHEN each command's source and display command are read, unerased and erased
- THEN the first three report Homebrew with a `brew ` prefix and the npm command reports npm with an
  `npm ` prefix
- AND each erased form equals its unerased form in source and display command
- Verification: `unit`

### Requirement: A brew argv can never name an npm package

`PackageTarget` construction MUST fail for an identity of kind `npm`, so no brew package command can be
built for it: the six brew verbs MUST report themselves unavailable for an npm entry rather than
produce an argv. A bulk selection MUST expand per package by source — brew identities into brew
commands, npm identities into npm commands — in selection order and through the one queue. Bulk pin,
unpin and reinstall MUST exclude npm identities from their eligible sets. The grouped `upgrade` (all)
MUST remain a bare `brew upgrade` naming no npm package; npm updates apply per package only. This MUST
be asserted structurally: no argv any brew command family can produce contains an npm identity.

#### Scenario: A brew verb is unavailable for an npm identity

- GIVEN the identity `(npm, typescript)`
- WHEN `PackageTarget` is constructed and each of the six brew verbs is requested for it
- THEN construction fails and every verb reports unavailable
- AND no argv containing `typescript` was produced by any brew command
- Verification: `unit`

#### Scenario: A mixed bulk upgrade fans out by source in selection order

- GIVEN a selection of `wget` (formula), `typescript` (npm) and `iterm2` (cask), in that order
- WHEN a bulk upgrade is built
- THEN exactly three operations are enqueued: `brew upgrade --formula wget`, `npm install -g
  typescript@latest`, `brew upgrade --cask iterm2`, in that order
- Verification: `unit`

#### Scenario: Pin, unpin and reinstall never see an npm identity

- GIVEN a selection holding one unpinned formula and one npm package
- WHEN the pin, unpin and reinstall eligible sets are read
- THEN none contains the npm identity
- Verification: `unit`

### Requirement: Mutations are serialized across sources through one FIFO

At most one mutation MAY be in flight across all sources. Queued mutations MUST run in submission
order regardless of source, so a brew mutation submitted after an npm mutation waits for it and vice
versa. Reads of either source MUST NOT be blocked by a mutation of the other. Cancel, activity
enumeration and history MUST treat both sources identically.

#### Scenario: A brew mutation waits for an in-flight npm mutation

- GIVEN an npm upgrade in flight
- WHEN a brew upgrade is submitted
- THEN the brew process is not spawned until the npm operation reaches a terminal outcome
- AND the enumeration reports the npm operation running and the brew one pending
- Verification: `unit`

#### Scenario: A brew read proceeds during an npm mutation

- GIVEN an npm mutation in flight
- WHEN a brew inventory refresh is requested
- THEN it starts and completes without waiting
- Verification: `unit`

## MODIFIED Requirements

### Requirement: No mutation is built or spawned when brew is absent or invalid

When brew detection reports absent, invalid, or a missing configured path, the capability MUST NOT
spawn any mutation. Mutation affordances MUST be unavailable rather than failing at spawn time,
nothing MUST be thrown or blocked, and the same read-only guidance the inventory surfaces MUST
apply. When brew later becomes available, mutations MUST become available without restarting the
app.

This rule MUST hold for every **Homebrew-sourced** command family submitted through the mutation
spine, not only for package mutations. Each family's own surface MUST render the same read-only
guidance rather than failing at spawn time, MUST spawn nothing while brew is absent or invalid, and
MUST become available again when brew appears without restarting the app.

Availability MUST be evaluated **per source**. A command whose source is npm MUST be gated by npm
detection and the npm preference alone, on the terms `npm-source` states, and MUST NOT be made
unavailable because brew is absent; a Homebrew-sourced command MUST NOT be made unavailable because
npm is absent or disabled. A submission for a source that has no attached runner MUST settle as a
launch failure recording exactly one history entry, on the terms `operation-activity` already states.
(Previously: the rule gated every family on brew detection alone, which would have made npm commands
unavailable on a Mac without Homebrew and left an npm-absent Mac unspecified.)

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

#### Scenario: Availability is independent per source

- GIVEN brew `absent` and npm detected, and separately brew detected and npm `absent`
- WHEN an npm upgrade and a brew upgrade are requested in each case
- THEN in the first case the npm upgrade is submitted and the brew one reports unavailable
- AND in the second the brew upgrade is submitted and the npm one reports unavailable, with guidance
  naming npm
- Verification: `unit`

#### Scenario: A source with no attached runner settles as a launch failure

- GIVEN a queue with a brew runner attached and no npm runner
- WHEN an npm upgrade is submitted
- THEN it settles as a failed launch, spawns nothing, and records exactly one history entry
- Verification: `unit`
