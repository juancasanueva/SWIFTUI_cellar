# Delta for installation-history

## MODIFIED Requirements

<!-- IH1 -->
### Requirement: Every mutation Cellar performs writes exactly one durable entry

Each operation Cellar submits through its mutation spine MUST produce exactly one history entry —
never zero and never two — at that operation's terminal outcome. The entry MUST carry the date it
reached that outcome, the package identity it acted on **when it has one**, the operation's verb, the
version it moved from and the version it moved to when both are known, its outcome, and the exact
argv the operation ran. Success, failure (including the typed sudo and busy failures and a launch
failure before a process exists) and cancellation MUST each be recorded. Nothing MUST be written
before the operation reaches a terminal outcome. Entries MUST survive an app relaunch.

The verb vocabulary MUST NOT be limited to package verbs. A non-package operation MUST record its own
typed verb — for services, exactly `serviceStart`, `serviceStop`, `serviceRestart` and `serviceRun`;
for tap mutations, exactly `tapAdd`, `tapUntap` and `tapForceUntap` — and MUST store a **null** package
identity. A non-package family MUST namespace its stored verbs so they cannot collide with a package
verb: the vocabulary already holds `install`, `upgrade`, `pin` and `upgradeAll`, and an IH5 search
must never leave the user unable to tell which family they matched. The namespaced forms still satisfy
IH5's case-insensitive bare-verb search because they contain their searchable service or tap terms.

Such an entry MUST NOT synthesize, borrow or infer a package identity from the operation's arguments:
the name of the service or tap the operation acted on MUST NOT be stored as a package identity, and
the version-from and version-to fields MUST be absent. The subject of a null-package entry remains
discoverable through its stored argv, which the searchable projection already matches. The existing
nullable history shape MUST represent tap entries without requiring a persistence schema migration.

A presentation of the history MUST NOT reconstruct an identity that storage refused to synthesize.
A null package identity and a grouped operation over every package are two different facts and MUST
NOT be rendered as one: an entry with no package identity MUST NOT be presented as acting on every
package, and MUST NOT be presented under the service or tap name as though it were a package.

Repetition MUST NOT be collapsed: N submitted operations produce N entries. The capability MUST NOT
deduplicate, coalesce, throttle or suppress an entry because an identical or opposite one was written
recently, and MUST NOT collapse a start/stop or tap/untap pair into a net change.

(Previously: the requirement covered namespaced service verbs and null-package presentation, but did
not define tap verbs, tap identities, launch-failure coverage for tap operations, or migration-free
representation of tap history.)

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
- THEN exactly four entries exist, one per operation, each carrying its own namespaced verb —
  `serviceStart`, `serviceStop`, `serviceRestart`, `serviceRun` — its outcome and its exact argv
- AND none of those four verbs is also a package verb
- AND every one of them carries a null package identity, no version-from and no version-to, and none
  stores `atuin` as a package identity

#### Scenario: A null-package entry is never displayed as a package or as every package

- GIVEN one recorded `services stop atuin` entry and one recorded grouped `upgradeAll` entry, both of
  which store no package identity
- WHEN the history is presented
- THEN the grouped entry is presented as acting on every package
- AND the service entry is presented as acting on no package, never as acting on every package and
  never under the name `atuin`

#### Scenario: Repeated toggling appends one entry per operation

- GIVEN the same service started and stopped five times, each operation reaching a terminal outcome
- WHEN the history is read
- THEN exactly ten entries exist, in submission order
- AND no pair was collapsed, deduplicated or netted out

#### Scenario: Each tap verb writes one null-package entry with exact argv

- GIVEN `tap acme/tools`, `untap acme/tools`, and `untap --force acme/tools` each reach a terminal outcome
- WHEN history is read
- THEN exactly three entries carry `tapAdd`, `tapUntap`, and `tapForceUntap`, their exact argvs and outcomes
- AND all have null package identity and absent version fields

#### Scenario: Tap launch failure and cancellation each record once

- GIVEN one tap mutation fails before process launch and another is cancelled while queued
- WHEN each reaches its terminal outcome
- THEN exactly one entry exists for each with its exact argv and distinct failure or cancelled outcome
- AND neither entry requires or invents a package identity

<!-- IH5 -->
### Requirement: History is searchable and ordered newest first

The history MUST be readable as an ordered projection, newest entry first. It MUST support a text
search that matches at least the package name, the operation verb — including the non-package service
verbs `start`, `stop`, `restart` and `run`, and tap terms `tap`, `untap` and `force` — and the argv,
case-insensitively. An empty search MUST return every entry. A search matching nothing MUST return an
empty result without removing, hiding or altering any stored entry.

An entry with no package identity MUST NOT be excluded from the projection or from search. Its argv
MUST remain matchable, so the subject of a non-package operation is findable by name even though no
package identity is stored for it. Namespaced tap verbs MUST remain distinguishable in results while
matching the bare tap terms by substring.

(Previously: search covered null-package service verbs and argv, but did not require tap, untap, or
force terms and namespaced tap verbs to be searchable.)

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

#### Scenario: Tap entries are findable by family, action, and target

- GIVEN entries with verbs `tapAdd`, `tapUntap`, and `tapForceUntap` for `acme/tools`
- WHEN history is searched in turn for `tap`, `untap`, `FORCE`, and `acme/tools`
- THEN each query returns exactly the entries whose verb or argv contains that term, case-insensitively
- AND every returned tap entry retains a null package identity
