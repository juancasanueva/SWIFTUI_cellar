# installation-history

A durable, append-only record of every mutation Cellar itself performed — date, package, verb,
version from→to, outcome and the exact argv — its searchable projection, its keep-all retention, and
the manual all-or-nothing clear action. Owned by `Packages/CellarCore` target `Persistence`.

This capability owns **what is recorded, how long it is kept, and how it is queried**. When a
terminal outcome occurs, and the one-record-per-terminal-outcome obligation, are owned by
`operation-activity` and referenced here, never restated. The execution layer's own bounded in-memory
records are owned by `brew-execution` and are a different thing entirely: this store is the durable
one.

## Requirements

### Requirement: Every mutation Cellar performs writes exactly one durable entry

Each mutation Cellar submits MUST produce exactly one history entry — never zero and never two — at
that operation's terminal outcome. The entry MUST carry the date it reached that outcome, the package
identity it acted on when it has one, the mutation verb, the version it moved from and the version it
moved to when both are known, its outcome, and the exact argv the operation ran. Success, failure
(including the typed sudo and busy failures) and cancellation MUST each be recorded. Nothing MUST be
written before the operation reaches a terminal outcome. Entries MUST survive an app relaunch.

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

### Requirement: A grouped upgrade is one entry; a fanned-out selection is one entry per package

"Upgrade all" MUST be recorded as a single entry for the whole grouped operation, carrying the argv
that ran and naming no package identity. The capability MUST NOT derive per-package entries for it by
diffing inventory snapshots either side of the operation. A selected bulk action, which the mutation
capability expands into one invocation per selected package, MUST therefore produce one entry per
selected package, each naming exactly that package.

#### Scenario: Upgrade all is one grouped entry

- GIVEN an upgrade-all operation that upgraded several packages and exited successfully
- WHEN the history is read
- THEN exactly one entry was written for it, carrying the argv `upgrade`
- AND it names no package identity, and no per-package entries were derived from an inventory diff

#### Scenario: A bulk selection produces one entry per package

- GIVEN a bulk upgrade over the formulae `wget` and `git` and the cask `iterm2`, in that order
- WHEN all three operations reach their terminal outcomes
- THEN exactly three entries exist, one naming each package, each carrying its own single-package
  argv

### Requirement: Only mutations submitted through Cellar are recorded

The history MUST record mutations Cellar itself submitted. A change made outside the app MUST NOT
produce an entry, even though the app detects it: an external change signal, and the re-snapshot it
triggers, MUST write nothing. Read-only probes — inventory refreshes, catalog syncs, detection —
MUST write nothing.

#### Scenario: An externally installed package is not logged

- GIVEN a running inventory and a change source under test control
- WHEN the underlying snapshot gains a package and a change signal is emitted, and the quiet window
  elapses
- THEN the inventory lists the new package
- AND the history contains no entry for it

#### Scenario: Read-only work writes nothing

- GIVEN an empty history
- WHEN an inventory refresh, a catalog sync and a brew detection all complete
- THEN the history is still empty

### Requirement: History is append-only and never auto-evicted

Retention MUST be keep-all: the capability MUST NOT impose an entry-count cap, an age cap, a rotation
policy or any other automatic eviction. An entry MUST NOT be rewritten or amended once written — a
later operation on the same package MUST append a new entry rather than update the previous one.
Retention here MUST be independent of the execution layer's own bounded in-memory records: retiring
those records MUST NOT remove or alter any history entry.

#### Scenario: Nothing is evicted as entries accumulate

- GIVEN a history to which a large number of entries has been appended across several sessions
- WHEN the history is read
- THEN every appended entry is still present
- AND no entry was removed by age or by count

#### Scenario: A later mutation appends rather than amends

- GIVEN an entry recording an install of the formula `wget`
- WHEN `wget` is later uninstalled and that operation reaches its terminal outcome
- THEN two entries exist for `wget`
- AND the first entry's fields are unchanged

#### Scenario: Retiring an execution record does not touch history

- GIVEN a recorded entry whose operation's execution-layer record has been retired
- WHEN the history is read
- THEN the entry is still present with all of its fields

### Requirement: History is searchable and ordered newest first

The history MUST be readable as an ordered projection, newest entry first. It MUST support a text
search that matches at least the package name, the mutation verb and the argv, case-insensitively. An
empty search MUST return every entry. A search matching nothing MUST return an empty result without
removing, hiding or altering any stored entry.

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

### Requirement: Clear history is a single confirmed all-or-nothing action

Clearing the history MUST require an explicit confirmation before anything is deleted. A confirmed
clear MUST remove every entry and MUST remove nothing else — locally stored favorites, notes and
snoozes MUST be untouched. Declining MUST delete nothing. The capability MUST NOT offer selective or
per-entry deletion.

A confirmed clear that fails MUST remain all-or-nothing and MUST be observable. Every entry MUST
still be present and readable afterwards, and the history MUST NOT be presented as emptied or as
healthy. The failure MUST be reported inline with a reason, through the projection's own availability
and error surface, and that reason MUST survive the projection reload that follows the attempt rather
than being overwritten by it. A failed clear MUST NOT raise a blocking alert and MUST NOT offer a
retry affordance.

#### Scenario: A confirmed clear empties the history

- GIVEN a history of several entries
- WHEN clear is requested and confirmed
- THEN the history is empty

#### Scenario: Declining deletes nothing

- GIVEN a history of several entries and a pending clear confirmation
- WHEN the confirmation is declined
- THEN every entry is still present

#### Scenario: A failed clear leaves every entry present and reports why

- GIVEN a history of three entries and a store whose deletion fails
- WHEN clear is requested and confirmed
- THEN all three entries are still present and readable, with their original fields
- AND the failure is reported with a reason rather than as an empty history

#### Scenario: A failed clear's reason survives the reload that follows it

- GIVEN a confirmed clear that has just failed
- WHEN the projection reloads after the attempt and its availability and error surface is read
- THEN the clear failure and its reason are still reported, not a healthy or available-and-empty
  history
- AND no blocking alert and no retry control is presented for it

#### Scenario: Clearing history leaves local metadata intact

- GIVEN stored favorites, notes and snoozes alongside a non-empty history
- WHEN clear is requested and confirmed
- THEN the history is empty
- AND every favorite, note and snooze is still readable with its original value

#### Scenario: No per-entry delete affordance exists

- WHEN the controls the history projection exposes for a single entry are enumerated
- THEN no delete or remove control is present for that entry

### Requirement: A recording failure never changes a mutation's outcome

Recording MUST be a side effect of a terminal outcome, never a precondition of it. If the recorder is
absent, unavailable, or fails while writing, the operation MUST still reach and report its own
terminal outcome unchanged, the forced inventory re-snapshot owed at that outcome MUST still happen
exactly once, and nothing MUST be thrown into the operation's path.

#### Scenario: An absent recorder does not affect the operation

- GIVEN no history recorder is configured
- WHEN a mutation reaches a successful terminal outcome
- THEN it is reported as successful and exactly one inventory re-snapshot is forced
- AND nothing is thrown

#### Scenario: A failing recorder does not affect the operation

- GIVEN a recorder that fails on every write
- WHEN a mutation reaches its terminal outcome
- THEN the operation's reported outcome is identical to the same run with a working recorder
- AND exactly one inventory re-snapshot is forced

## Provenance

- Established by change `m2-local-metadata-history` (archived `2026-08-03`, PRD milestone **M2**,
  slice M2-3 — the last M2 slice), ADDED-only delta — **7 requirements / 21 scenarios**, promoted
  verbatim from
  `openspec/changes/archive/2026-08-03-m2-local-metadata-history/specs/installation-history/spec.md`.
  This is the first main spec for the capability; nothing was modified, removed or renamed. This file
  adds only the header, the `## Requirements` wrapper and this provenance section. **No archive
  reconciliation was needed** — the promoted text is byte-identical to the delta's requirement and
  scenario bodies.
- Binding product decisions settled **before** the delta was written (user-confirmed 2026-08-02,
  Engram `#7111`), stated in it as facts rather than open questions:
  - **"Upgrade All" is one grouped entry** — no per-package attribution and no inventory-snapshot
    diffing. The absence of diffing is asserted structurally by
    `OperationCenterHistoryTests > noInventoryDiffingProducesARecord`, not merely by convention.
  - **History records Cellar-submitted mutations only** — externally detected brew changes are
    deliberately not logged, even though the change observer makes them visible. Verified live during
    manual check 9.2(c): `brew install hello cowsay` from Terminal surfaced both packages in Installed
    through the FSEvents watcher and wrote **zero** history rows.
  - **Clear history is all-or-nothing with a confirmation** — selective row deletion is out of scope.
  - **Retention is keep-all** — nothing is auto-evicted by age or by count. Enforced structurally:
    verify's repo-wide scan for `fetchLimit` returns exactly one hit, a comment in
    `HistoryStore.swift` stating why there is none, and
    `HistoryStoreTests > nothingIsEvictedAsEntriesAccumulate` appends 750 entries across three
    sessions.
- **`operation-activity` owns the trigger, this capability owns the record.** OA's "Every terminal
  outcome records exactly one history entry" is the counterpart to this capability's "Every mutation
  Cellar performs writes exactly one durable entry"; the two are written to be read together and MUST
  NOT drift. Recording reaches the execution side through a `HistoryRecording` protocol seam whose
  default is a no-op, so `BrewClient` never links SwiftData and dropping the seam returns the
  operation centre to its pre-history behaviour exactly.
- **A persisted argv is display-only.** The stored `commandText` is the operation's argv joined by
  spaces and the only control a row exposes is copy — proven by
  `HistoryRecorderTests > aStoredRowCannotBecomeACommand` (no `-> MutationCommand`,
  `MutationCommand(`, `brewCommand` or `PackageTarget(` declaration exists anywhere in `Persistence`)
  and `theOnlyControlIsCopy`. A stored row can never be replayed into a spawned process.
- **Verification note on "Clear history is a single confirmed all-or-nothing action"** (verify,
  2026-08-03): the scenario "Declining deletes nothing" is a UI-only affordance with no store-level
  seam, and it is evidenced by a **recorded manual observation** (task 9.2 d-addendum, commit
  `3bf14fd`) rather than by an automated test — with one history row present, the Clear dialog was
  opened, **Cancel** pressed, and the row remained. Structurally, `HistoryView.swift` places
  `clearAll()` inside the `role: .destructive` button only, and `clearAll()` is the store's sole
  deleting API (`HistoryStoreTests > noPerEntryDeleteControlExists`). Converting this into an
  automated regression gate is registered as follow-up **VS3** in the M2-3 archive report.
- ~~**Known follow-up (`m2-local-metadata-history` native review lineage `review-e07590a04c4aff38`,
  WARNING, non-blocking)**: a **failed** Clear History is silently masked — `clearAll()` sets the
  availability reason and then an unconditional `reload()` overwrites it back to `.available` while
  `lastError` is never set (`HistoryStore.swift:181-190`), so a clear that did not delete can render
  as if it had.~~ **CLOSED by `m3-hardening-prelude` (M3-0, archived 2026-08-03)** — see the
  amendment below, which turns the silent mask into requirement text.
- **Amended by change `m3-hardening-prelude` (archived `2026-08-03`, PRD milestone **M3**, slice
  M3-0 — the hardening prelude)**: **1 MODIFIED** requirement replaced as a whole block — "Clear
  history is a single confirmed all-or-nothing action" — adding **2 scenarios**. 7 requirements / 21
  scenarios → **7 requirements / 23 scenarios**. Nothing was added, removed or renamed; the other six
  requirements are byte-identical, and the replacement is a strict superset of the text it replaced.
  Previously the requirement governed only a *confirmed* clear and a *declined* clear; a clear that
  **failed** was undefined, and the delivered code presented it as an emptied, healthy history with
  no reason reported — M2-3 follow-up **W2**.
  - **The surface is inline, with no alert and no retry** (settled product decision Q1, 2026-08-03,
    Engram `#7130`): the reason travels through the projection's existing availability and
    `lastError` surface. Entries stay visible; the clear stays all-or-nothing.
  - Delivered by an internal `init(container:clearing:)` seam — an **injected closure**, deliberately
    not a filesystem-permission fake (design D5) — plus a `clearAll()` that now calls `reload()`
    **first** and applies `availability = .unavailable(reason:)` and `lastError` **after**. Reloading
    afterwards was the bug itself. Pinned by `HistoryStoreTests >
    aFailedClearKeepsEveryEntryAndReportsTheReason` and `aSuccessfulClearLeavesNoStaleFailureReason`.
  - **Manual-coverage boundary, stated rather than papered over**: forcing a SwiftData delete to
    throw is not reliably reachable through the UI, so the failed-clear path's runtime evidence is
    the headless seam tests. Manual check 9.1(d) confirmed only the reachable half — Clear presents a
    confirmation with no blocking alert and no retry control.
- **Known follow-up (`m3-hardening-prelude` native review lineage `review-fa82e5eaa3023fc4`,
  WARNING, non-blocking — introduced by this slice's own fix)**: the failed-clear reason is durable
  only **until the next reload**. The history search field reloads the projection on every keystroke
  (`didSet`), and that reload sets `availability` back to `.available` while `lastError` survives —
  so the *availability* half of the surface, which this requirement names, can be cleared by an
  unrelated interaction. Every scenario is COMPLIANT as written: the requirement binds the reason to
  "the projection reload that **follows the attempt**", which the delivery satisfies. The gap is that
  a reader may reasonably expect the reason to persist until acknowledged. Tracked as follow-up
  **(a)** in the M3-0 archive report — the top absorption candidate for M3-1, either as a fix or as a
  deliberate spec clarification of how long the reason must live.
