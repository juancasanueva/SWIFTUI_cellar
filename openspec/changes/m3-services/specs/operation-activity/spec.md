# Delta for operation-activity

Existing capability — `openspec/specs/operation-activity/spec.md` (6 requirements / 23 scenarios).

Delta summary: **1 MODIFIED requirement — 6 scenarios (5 carried forward, 1 added)**. The MODIFIED
requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED, REMOVED or
RENAMED. 6 requirements / 23 scenarios → **6 requirements / 24 scenarios**.

**OA1 needs no change and is deliberately not reproduced here.** It already requires each item to
carry "the package identity it acts on **when it has one**", so a non-package operation is already
in contract. OA2 (copy command), OA3 (log streaming), OA4 (cancel) and OA5 (summary/detail) are
likewise unchanged: they are written against the operation, not against a package, and a service verb
gets its own queue item, its own live log, its own cancel and its own copy-command for free.

Only OA6 needs text, for two reasons: the exactly-one-entry rule has to say what "one entry" means
for an operation with no package identity, and its side-effect clause names "the forced re-snapshot"
in the singular while `package-mutation` PM6 is becoming a per-domain declaration in this same slice.

## MODIFIED Requirements

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
