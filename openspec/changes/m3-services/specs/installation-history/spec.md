# Delta for installation-history

Existing capability — `openspec/specs/installation-history/spec.md` (7 requirements / 23 scenarios).

Delta summary: **3 MODIFIED requirements — 14 scenarios (10 carried forward, 4 added)**. Every
MODIFIED requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED,
REMOVED or RENAMED. 7 requirements / 23 scenarios → **7 requirements / 27 scenarios**.

**Binding product ruling, settled before this delta was written** (user, 2026-08-03, Engram `#7180`
ruling a), stated here as a fact rather than an open question:

> **Service toggles DO write history.** All four verbs — `start`, `stop`, `restart`, `run` — each
> write exactly **one** entry with a **null package identity** and a typed service verb. This honours
> IH1 as written (the funnel writes by construction), keeps one auditable trail of everything Cellar
> submitted, and is the least new code. The accepted cost is a chatty history under repeated
> toggling; that cost is made explicit below rather than papered over.

**IH3 ("Only mutations submitted through Cellar are recorded") gets NO carve-out and is untouched.**
Rejected alternatives, recorded so the decision is not silently reopened: an IH3 carve-out excluding
service verbs; recording start/stop only; a separate services activity store. IH2 (grouped upgrade),
IH4 (append-only retention) and IH6 (clear history) are likewise untouched.

| Req | Change |
|---|---|
| **IH1** "Every mutation Cellar performs writes exactly one durable entry" | Defines the non-package verb vocabulary, the null-package form, and that repetition is never collapsed |
| **IH5** "History is searchable and ordered newest first" | The four service verbs enter the searchable vocabulary; a null-package entry stays findable through its argv |
| **IH7** "A recording failure never changes a mutation's outcome" | Its "forced inventory re-snapshot ... exactly once" clause is scoped to the domains the operation invalidates, so it stops contradicting `package-mutation` PM6 |

## MODIFIED Requirements

### Requirement: Every mutation Cellar performs writes exactly one durable entry

Each operation Cellar submits through its mutation spine MUST produce exactly one history entry —
never zero and never two — at that operation's terminal outcome. The entry MUST carry the date it
reached that outcome, the package identity it acted on **when it has one**, the operation's verb, the
version it moved from and the version it moved to when both are known, its outcome, and the exact
argv the operation ran. Success, failure (including the typed sudo and busy failures) and
cancellation MUST each be recorded. Nothing MUST be written before the operation reaches a terminal
outcome. Entries MUST survive an app relaunch.

The verb vocabulary MUST NOT be limited to package verbs. A non-package operation MUST record its own
typed verb — for services, exactly `start`, `stop`, `restart` and `run` — and MUST store a **null**
package identity. Such an entry MUST NOT synthesize, borrow or infer a package identity from the
operation's arguments: the name of the service the operation acted on MUST NOT be stored as a package
identity, and the version-from and version-to fields MUST be absent. The subject of a null-package
entry remains discoverable through its stored argv, which the searchable projection already matches.

Repetition MUST NOT be collapsed: N submitted operations produce N entries. The capability MUST NOT
deduplicate, coalesce, throttle or suppress an entry because an identical or opposite one was written
recently, and MUST NOT collapse a start/stop pair into a net change.
(Previously: the requirement was written for package mutations, so the verb vocabulary and the shape
of an entry with no package identity were undefined, and nothing said whether repeated identical
operations may be collapsed.)

#### Scenario: A successful mutation writes one complete entry

- GIVEN an install submitted for the cask `iterm2` that exits with status 0
- WHEN it reaches its terminal outcome
- THEN exactly one history entry exists for it
- AND it carries the cask identity, the install verb, the successful outcome and the argv
  `install --cask iterm2`

#### Scenario: Failed and cancelled mutations are recorded too

- GIVEN one mutation that exits non-zero, one that ends in the typed busy failure, and one that is
  cancelled while running
- WHEN each reaches its terminal outcome
- THEN exactly one entry exists for each
- AND each entry names its own outcome rather than a generic one

#### Scenario: Nothing is written before the terminal outcome

- GIVEN a mutation that has been submitted and is still running
- WHEN the history is read
- THEN it contains no entry for that operation

#### Scenario: History survives a relaunch

- GIVEN three recorded entries
- WHEN the store is closed and reopened against the same location
- THEN all three entries are present with their original fields

#### Scenario: Each service verb writes one entry with a null package identity

- GIVEN the four operations `services start atuin`, `services stop atuin`, `services restart atuin`
  and `services run atuin`, each reaching a terminal outcome
- WHEN the history is read
- THEN exactly four entries exist, one per operation, each carrying its own verb — `start`, `stop`,
  `restart`, `run` — its outcome and its exact argv
- AND every one of them carries a null package identity, no version-from and no version-to, and none
  stores `atuin` as a package identity

#### Scenario: Repeated toggling appends one entry per operation

- GIVEN the same service started and stopped five times, each operation reaching a terminal outcome
- WHEN the history is read
- THEN exactly ten entries exist, in submission order
- AND no pair was collapsed, deduplicated or netted out

### Requirement: History is searchable and ordered newest first

The history MUST be readable as an ordered projection, newest entry first. It MUST support a text
search that matches at least the package name, the operation verb — including the non-package service
verbs `start`, `stop`, `restart` and `run` — and the argv, case-insensitively. An empty search MUST
return every entry. A search matching nothing MUST return an empty result without removing, hiding or
altering any stored entry.

An entry with no package identity MUST NOT be excluded from the projection or from search. Its argv
MUST remain matchable, so the subject of a non-package operation is findable by name even though no
package identity is stored for it.
(Previously: the searchable vocabulary named only the package verbs, and nothing said that a
null-package entry stays listed and matchable.)

#### Scenario: Entries are ordered newest first

- GIVEN three entries recorded in a known order
- WHEN the history projection is read with an empty search
- THEN all three are returned, most recent first

#### Scenario: Searching by package name narrows the list

- GIVEN entries for `wget` and for `iterm2`
- WHEN the history is searched for `WGET`
- THEN only the `wget` entry is returned

#### Scenario: Searching by verb narrows the list

- GIVEN one install entry and one uninstall entry
- WHEN the history is searched for `uninstall`
- THEN only the uninstall entry is returned

#### Scenario: A search matching nothing is empty and non-destructive

- GIVEN a history of three entries
- WHEN it is searched for a term matching none of them, and then searched again with an empty term
- THEN the first search returns nothing and the second returns all three

#### Scenario: A null-package service entry is findable by verb and by its argv

- GIVEN one entry for `services stop atuin` with a null package identity and one entry for
  `install --formula wget`
- WHEN the history is searched for `STOP`, and then for `atuin`
- THEN each search returns only the service entry
- AND the service entry is present in the unfiltered, newest-first projection as well

### Requirement: A recording failure never changes a mutation's outcome

Recording MUST be a side effect of a terminal outcome, never a precondition of it. If the recorder is
absent, unavailable, or fails while writing, the operation MUST still reach and report its own
terminal outcome unchanged, every refresh owed at that outcome MUST still happen exactly once for
each state domain the operation invalidates, and nothing MUST be thrown into the operation's path. An
operation that invalidates no state domain MUST still reach and report its terminal outcome
unchanged.
(Previously: the requirement promised "the forced inventory re-snapshot owed at that outcome MUST
still happen exactly once" for every operation, which contradicts `package-mutation`'s typed
invalidation scope — an operation that cannot change the installed set owes zero inventory
re-snapshots, not one.)

#### Scenario: An absent recorder does not affect the operation

- GIVEN no history recorder is configured
- WHEN a mutation declaring the installed set reaches a successful terminal outcome
- THEN it is reported as successful and exactly one inventory re-snapshot is forced
- AND nothing is thrown

#### Scenario: A failing recorder does not affect the operation

- GIVEN a recorder that fails on every write
- WHEN a mutation declaring the installed set reaches its terminal outcome
- THEN the operation's reported outcome is identical to the same run with a working recorder
- AND exactly one inventory re-snapshot is forced

#### Scenario: A failing recorder does not affect a non-package operation either

- GIVEN a recorder that fails on every write
- WHEN an operation with no package identity reaches its terminal outcome
- THEN its reported outcome is identical to the same run with a working recorder
- AND exactly one refresh is forced for each domain it declared, and none for any it did not
- AND nothing is thrown
