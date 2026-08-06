# Delta for catalog-sync

Existing capability — `openspec/specs/catalog-sync/spec.md` (14 requirements / 51 scenarios).

Delta summary: **2 MODIFIED requirements** (reproduced in full so the archive step loses nothing) and
**2 ADDED requirements**. Nothing is REMOVED or RENAMED. Capability total after the merge:
**16 requirements / 66 scenarios**.

- *Slim persisted projection with a state sidecar* — 9 scenarios (6 carried forward byte-identical,
  3 added) — the exact-in-both-directions version gate now binds **every** file the catalog persists,
  not only the snapshot and the state sidecar, and each additional file is gated against the version
  **its own owning schema** declares, so the files gate independently in both directions; and the
  recorded footprint bound is pinned to the snapshot alone, so new durable state cannot be admitted by
  re-basing it.
- *Inspection data costs no new acquisition* — 3 scenarios (1 carried forward byte-identical, 1 edited,
  1 added) — the persisted-artefact list is widened from two files to four, and only to those four.
  The edited scenario is *The widened sync issues no additional request*, whose closing `AND` line
  enumerated the persisted files; every other line of the block is byte-identical.
- **ADDED** *A durable known-package roster records what this machine has already seen* — 6 scenarios
  — the seen-set that makes newness derivable at all, with the first-run rule, the no-cache gate, the
  never-fatal rule, and the prohibition on it entering `CatalogSnapshot`.
- **ADDED** *The dated arrivals log retains thirty days and prunes itself* — 5 scenarios — the small
  dated companion to the roster, its retention window, and its read-side and write-side pruning.

Traceability: **D2** → both ADDED requirements (the 30-day window and its dated log); the
**mechanism correction** recorded with the proposal decisions (Engram obs 7493) → the roster being a
durable file rather than a revision ordinal, and the MUST NOT against a `CatalogPackage` field;
**D3**, **D1**, **D4** and **D5** have no `catalog-sync` behaviour and are carried by the
`package-discovery` delta.

**Why the roster is a separate file, stated as a constraint rather than a design note.** Slice 1
closed with 2.4% of encoded-footprint headroom (1.56× measured against a 1.6× bound) over ~16k
records, so a persisted per-record first-seen field crosses the bound at any plausible size. The
requirements below therefore forbid newness data on `CatalogPackage` and inside `CatalogSnapshot`,
and require `CatalogFootprintTests` to keep passing **unchanged** rather than being re-based. That is
the gate this slice is checked against; it is not a preference.

**The newness sidecars are versioned independently of the snapshot.** What the hard constraint
mandates is the gate *idiom* — exact in both directions, absence-not-error, never mutating the file
it rejects — not the shared constant. Keying the roster and the arrivals log to the snapshot's
`schemaVersion` would make any unrelated projection bump silently erase the user's retained arrivals
history, which breaks **D2**'s 30-day retention promise for a reason the user never caused. The
requirements below therefore gate each additional file against the version *its own* owning schema
declares, and state the independence in both directions explicitly.

## MODIFIED Requirements

### Requirement: Slim persisted projection with a state sidecar

A successful sync MUST persist a slim projection containing only the fields the search and detail
capabilities require, plus a state sidecar recording, per source, `schemaVersion`, the validators
(`etag` and/or `lastModified`), `downloadedAt`, and `recordCount`. A persisted file whose
`schemaVersion` does not match the one the running build expects MUST be treated as no cache — the
system MUST re-sync from scratch and MUST NOT fail or crash on it.

The version check MUST apply independently to **every file the catalog persists** — the snapshot, the
state sidecar, and each additional sidecar this capability owns — so no file can be adopted on the
strength of another's version, nor rejected on the strength of another's version. The check MUST be
exact inequality in both directions: a version older than the running build's and a version newer
than it are the same answer, "no cache". Adding a field to the persisted projection MUST therefore be
accompanied by a `schemaVersion` increment, and reverting that increment MUST leave the newer file
classified as no cache rather than decoded with missing fields. Persisting an *additional file* that
adds no field to the projection MUST NOT require an increment: such a file MUST record the version
**its own owning schema declares**, which MAY be versioned independently of the snapshot's
`schemaVersion`, and MUST be classified by exactly the same exact-in-both-directions gate against
that owning schema's expected version. It follows that an increment of the snapshot's `schemaVersion`
MUST NOT invalidate an additional file whose own schema version still matches, and an increment of an
additional file's own schema MUST NOT invalidate the snapshot — the files gate independently.
Classification MUST NOT throw, MUST NOT be reported through a failure status, and MUST NOT mutate or
delete the file it rejected.

The persisted projection MUST stay within a recorded footprint bound, measured over a full-scale
catalog, covering the persisted snapshot's size on disk, the resident memory of a loaded snapshot,
and the time to load it. That bound MUST be asserted by an automated test rather than stated as a
comment, so a later widening that breaks it fails a test instead of a user's machine. If the
measurement shows the bound cannot be held with the full projection, the projection MUST be narrowed;
under any such narrowing the cask `url`, `sha256`, `depends_on` and `conflicts_with` values MUST be
retained. That bound is measured over the snapshot **alone**: a change that persists additional
durable state MUST NOT be admitted by re-basing it, the snapshot bound MUST keep holding with its
recorded value unchanged, and every additional persisted file MUST carry its own separately recorded
size bound, likewise asserted by an automated test rather than by a comment.
(Previously: the version gate named exactly two persisted files, said nothing about a file that adds
no projection field or about that file carrying a version of its own, and the footprint bound did not
state that it is measured over the snapshot alone, so persisting new state elsewhere had no stated
bound of its own.)

#### Scenario: State sidecar round-trips

- GIVEN a completed sync of 7,000 formulae and 8,500 casks
- WHEN the persisted state is read back
- THEN it reports `recordCount` 7,000 and 8,500 for the respective sources, a `downloadedAt`, the
  current `schemaVersion`, and the validators returned by the source

#### Scenario: Unknown schema version is treated as no cache

- GIVEN a persisted sidecar whose `schemaVersion` is greater than the one this build expects
- WHEN the catalog loads
- THEN it reports no usable cache, no error is thrown, and a full sync is scheduled

#### Scenario: A snapshot written by the previous schema is a cold start

- GIVEN a persisted snapshot whose `schemaVersion` is `1`, holding 15,000 readable records, beside a
  sidecar recording validators for both sources
- WHEN a build expecting `schemaVersion` 2 loads the catalog
- THEN it reports no usable cache, nothing is thrown, and the ordinary cold-launch progression runs
- AND the next sync re-downloads both payloads rather than revalidating into the rejected snapshot

#### Scenario: A sidecar written by the previous schema is rejected independently

- GIVEN a persisted snapshot at the current `schemaVersion` beside a sidecar whose `schemaVersion` is
  `1`
- WHEN the catalog loads
- THEN the sidecar is classified as no state, nothing is thrown, and no validator from it is replayed

#### Scenario: Rollback is symmetric

- GIVEN a persisted snapshot and sidecar written at `schemaVersion` 2
- WHEN a build that expects `schemaVersion` 1 loads the catalog
- THEN both files are classified as no cache, nothing is thrown, and one full sync restores service
- AND neither file was rewritten or deleted by the read

#### Scenario: The full-catalog footprint stays within its recorded bound

- GIVEN the full published catalog decoded with the widened projection
- WHEN the persisted snapshot size, the resident memory of the loaded snapshot, and the load time are
  measured
- THEN each is within the recorded bound, and the assertion fails if any of the three exceeds it

#### Scenario: New durable state does not move the snapshot bound

- GIVEN a build that persists the newness sidecars beside the snapshot
- WHEN the full-catalog footprint measurement runs
- THEN the snapshot's recorded bound and its recorded values are unchanged from the previous build's
- AND the measurement passes without the bound being re-based

#### Scenario: An additional sidecar is gated on exactly the same terms

- GIVEN a persisted sidecar this capability owns whose recorded version differs, in either direction,
  from the version its own owning schema expects
- WHEN the catalog loads it
- THEN it is classified as absent, nothing is thrown, no failure status is reported, and the file is
  neither rewritten nor deleted by the read

#### Scenario: A snapshot schema bump does not invalidate an independently versioned sidecar

- GIVEN a persisted sidecar this capability owns, recorded at the version its own schema expects,
  beside a snapshot and state sidecar written under a `schemaVersion` this build no longer expects
- WHEN the catalog loads
- THEN the snapshot and state sidecar are classified as no cache and a full sync is scheduled
- AND the additional sidecar is still classified as present and readable, so nothing it holds is
  discarded by the snapshot's version change

### Requirement: Inspection data costs no new acquisition

Every inspection field MUST be derived from the payload resources the catalog already acquires. This
capability MUST NOT gain a new brew invocation, a new remote resource, a per-package request, or any
request issued as a consequence of a package's detail being resolved. Resolving detail MUST remain
answerable from the persisted snapshot alone, with the network unreachable and no `brew` binary
present. Retaining a raw payload on disk beyond the sync that produced it is likewise excluded: the
persisted artefacts are exactly the snapshot, its state sidecar, the known-package roster and the
dated arrivals log — and nothing else. Deriving newness locally MUST NOT introduce a request of any
kind: the roster and the arrivals log are written from data the sync already holds.
(Previously: the persisted artefacts were exactly the snapshot and its state sidecar, and the
requirement said nothing about locally derived newness.)

#### Scenario: Inspection fields resolve offline and without brew

- GIVEN a persisted snapshot containing a cask with inspection fields, brew detection reporting
  `absent`, and a source that fails every request
- WHEN that cask's detail is resolved
- THEN every inspection field is served from the snapshot
- AND no brew process was spawned and no request was issued

#### Scenario: The widened sync issues no additional request

- GIVEN a fake `CatalogSource` that records each request
- WHEN a sync runs on a build carrying the widened projection
- THEN the recorded requests are exactly the payload and analytics resources the previous build
  requested — no additional resource and no per-package request
- AND no file other than the snapshot, its state sidecar, the known-package roster and the arrivals
  log remains in the catalog directory

#### Scenario: Deriving newness issues no request

- GIVEN a fake `CatalogSource` that records each request and a persisted roster from an earlier sync
- WHEN a sync runs, updates the roster and records arrivals
- THEN the recorded requests are exactly the payload and analytics resources, with no additional
  resource and no per-package request

## ADDED Requirements

### Requirement: A durable known-package roster records what this machine has already seen

A sync that publishes a snapshot MUST record, in a durable file owned by the catalog's file store
beside the snapshot, the set of package identities that snapshot contains. The roster MUST carry
identities only — no dates, no counts, no per-record payload — and it MUST be gated by the same
exact-in-both-directions version check every other persisted file is, applied against the version its
own owning schema declares rather than against the snapshot's `schemaVersion`: a missing, corrupt,
unreadable or version-mismatched roster MUST all mean the same thing, "this machine has seen
nothing", and MUST NOT be reported as an error, MUST NOT throw, and MUST NOT mutate or delete the
file it rejected. Because the roster is versioned independently, a change to the snapshot's
`schemaVersion` MUST NOT discard it.

Newness MUST be derived from this roster. It MUST NOT be derived from `CatalogSnapshotRevision` or
any other process-local ordinal, which restarts at 1 on every launch. The roster MUST NOT be carried
inside `CatalogSnapshot`, and no field recording newness, first observation, or seen-ness MUST be
added to `CatalogPackage`; the persisted snapshot's shape and its `schemaVersion` MUST be unchanged
by this capability, and the recorded snapshot footprint bound MUST keep passing with its existing
values.

A sync whose payloads all revalidated as unchanged MUST leave the roster describing the same set, so
it produces no arrivals. Reading or writing the roster MUST NOT be able to fail a sync: a roster that
cannot be read is "seen nothing" and a roster that cannot be written MUST leave the sync's success,
its published snapshot and its state sidecar unaffected. The roster MUST stay within its own recorded
size bound at full catalog scale, asserted by an automated test.

#### Scenario: The first sync seeds the roster and reports no arrivals

- GIVEN no roster on disk
- WHEN a first sync publishes a snapshot of 15,000 packages
- THEN the roster records all 15,000 identities
- AND no package is recorded as an arrival

#### Scenario: The second sync reports only what the roster had not seen

- GIVEN a roster seeded by a previous sync
- WHEN a sync publishes a snapshot containing one package the roster does not hold
- THEN exactly that package is recorded as an arrival
- AND the roster afterwards holds every identity in the new snapshot

#### Scenario: A missing, corrupt or mismatched roster means "seen nothing"

- GIVEN, in turn, no roster file, a roster whose bytes are not valid JSON, and a roster whose
  recorded version differs from the version its own owning schema expects
- WHEN each is read
- THEN each is classified as "seen nothing", nothing is thrown, no failure status is reported, and the
  rejected file is neither rewritten nor deleted by the read
- AND the next sync re-seeds the roster and records no arrivals

#### Scenario: A roster write failure does not fail the sync

- GIVEN a file store whose roster write fails while the snapshot and state writes succeed
- WHEN a sync runs
- THEN the sync reports success, the snapshot is persisted and served, and the state sidecar is intact

#### Scenario: An unchanged sync produces no arrivals

- GIVEN a persisted snapshot and roster, and a source reporting both payload resources unchanged
- WHEN a sync runs
- THEN no package is recorded as an arrival and the roster still describes the same set

#### Scenario: The snapshot is untouched and stays within its bound

- GIVEN a build persisting the roster
- WHEN the persisted snapshot is inspected and the full-catalog footprint measurement runs
- THEN the snapshot carries no roster, no first-seen date and no seen-ness field on any package
- AND `schemaVersion` is unchanged and the footprint measurement passes with its existing recorded
  bound
- AND the roster's own recorded size bound holds at full catalog scale

### Requirement: The dated arrivals log retains thirty days and prunes itself

Arrivals MUST be persisted in a file separate from the roster, holding one dated entry per package
identity the diff found new. Only this file carries dates. An entry's date MUST be the moment the
package was **first observed by this installation**, taken from the same time source the sync uses to
record `downloadedAt`, and it MUST NOT be a publication or release date. An identity already present
in the log MUST keep its original date and MUST NOT gain a second entry, however often it is observed
again.

An entry whose date is more than 30 days before now MUST NOT be projected, and it MUST be removed
from the file no later than the next write, so the log cannot grow without bound. An entry whose date
is missing or unreadable MUST be dropped rather than failing the read. The log MUST be gated, on
absence, corruption and version, exactly as the roster is — against the version its own owning schema
declares, not the snapshot's: unreadable means "no arrivals", never an error. Because that version is
independent of the snapshot's, an increment of the snapshot's `schemaVersion` MUST NOT erase a user's
retained arrivals history. The log MUST stay within its own recorded size bound.

#### Scenario: A newly observed package is dated on first observation

- GIVEN a roster that does not hold formula `newpkg` and a sync running at a controlled time `T`
- WHEN the sync publishes a snapshot containing `newpkg`
- THEN the arrivals log holds one entry for `newpkg` dated `T`

#### Scenario: A re-observed package keeps its original date

- GIVEN an arrivals log holding `newpkg` dated 10 days ago
- WHEN a later sync observes `newpkg` again
- THEN the log still holds exactly one entry for `newpkg`, still dated 10 days ago

#### Scenario: An entry beyond the window is pruned on the next write

- GIVEN an arrivals log holding one entry dated 31 days ago and one dated 2 days ago
- WHEN the log is read, and then a later sync writes it
- THEN the read yields only the 2-day-old entry
- AND the file afterwards holds only the 2-day-old entry

#### Scenario: An unreadable log means "no arrivals"

- GIVEN, in turn, no arrivals file, a file whose bytes are not valid JSON, and a file whose recorded
  version differs from the version its own owning schema expects
- WHEN each is read
- THEN each yields no arrivals, nothing is thrown, and no failure status is reported

#### Scenario: An undatable entry is dropped, not fatal

- GIVEN an arrivals log holding one entry with no readable date beside two well-formed entries
- WHEN it is read
- THEN the two well-formed entries are returned and the undatable one is absent
- AND nothing is thrown
