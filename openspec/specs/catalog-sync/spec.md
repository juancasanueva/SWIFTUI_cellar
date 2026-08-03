# catalog-sync

Acquiring, revalidating, decoding, persisting and refreshing the Homebrew catalog
(`homebrew/core` formulae + `homebrew/cask` casks) and its 365-day analytics counts. Owned by
`Packages/CellarCore` target `Catalog`.

## Requirements

### Requirement: Acquisition behind a source seam, independent of brew

Catalog acquisition MUST go through a `CatalogSource` seam that yields, per source kind
(`formula`, `cask`), either an updated payload or an explicit "unchanged" result. Sync MUST NOT
require a `brew` binary to be present, MUST NOT invoke `brew`, and MUST NOT read brew's caches.
The transport MUST stream payloads to disk rather than materialising them in memory, sized for a
combined payload of at least 40 MB.

#### Scenario: Sync succeeds while brew is absent

- GIVEN brew detection reports `absent` and a fake `CatalogSource` serving both payloads
- WHEN a sync runs
- THEN it completes successfully and the catalog is queryable
- AND no brew process was spawned

#### Scenario: Every network read goes through the seam

- GIVEN a fake `CatalogSource` that records each request and a transport that fails if used directly
- WHEN a sync runs
- THEN the fake recorded exactly one request per source kind and the sync never touched the network

### Requirement: Conditional revalidation without full re-download

Each sync MUST send the stored validators for that source (`If-Modified-Since` from the recorded
`lastModified`, and `If-None-Match` from the recorded `etag` when one was stored). When the origin
signals the payload is unchanged, the sync MUST revalidate without re-downloading or re-decoding
the payload, MUST keep the existing snapshot, and MUST record a new `downloadedAt`. When no
validators are stored, the request MUST be unconditional. Cached-response reuse MUST NOT mask the
unchanged signal — an unchanged response MUST be observable as such.

#### Scenario: Unchanged payload is not re-downloaded

- GIVEN a persisted snapshot whose state records `lastModified` for both sources
- WHEN a sync runs and the source reports both sources unchanged
- THEN no payload body was read and no new snapshot was written
- AND the previously persisted snapshot is still served and `downloadedAt` advanced

#### Scenario: Changed payload replaces the snapshot

- GIVEN a persisted snapshot recording validator `V1`
- WHEN a sync runs and the source returns a changed payload with validator `V2`
- THEN a new snapshot is persisted and the recorded validator is `V2`

#### Scenario: First sync sends no validators

- GIVEN no persisted catalog state
- WHEN a sync runs
- THEN the recorded request carried neither `If-Modified-Since` nor `If-None-Match`

### Requirement: Full-replace snapshot semantics with atomic swap

A successful sync MUST replace the persisted snapshot wholesale. A package present in the previous
snapshot but absent from the new payload MUST disappear from all queries; the system MUST NOT keep
tombstones, merge, or diff records across syncs. The replacement MUST be atomic: a reader MUST
observe either the complete previous snapshot or the complete new one, never a partial file.

#### Scenario: A package absent from the new dump is gone

- GIVEN a persisted snapshot containing formula `oldpkg`
- WHEN a sync completes with a payload that does not contain `oldpkg`
- THEN a lookup for `oldpkg` returns not-found and it appears in no search result

#### Scenario: An interrupted write leaves the previous snapshot readable

- GIVEN a persisted snapshot and a file store whose write fails midway through persistence
- WHEN a sync runs
- THEN the sync reports `.persistence` failure
- AND the previously persisted snapshot still loads and is served unchanged

### Requirement: A failed sync never erases the last good catalog

Sync failures MUST be reported as exactly one case of a closed `CatalogSyncError` enumeration:
`offline`, `httpStatus(Int)`, `malformedPayload`, `persistence`, or `cancelled`. On any failure the
previously persisted snapshot and its state MUST remain intact, loadable and served. Retryable
failures (transport errors, `429`, and `5xx`) MUST be retried with backoff; other `4xx` statuses
MUST NOT be retried.

#### Scenario: Offline sync preserves the cached catalog

- GIVEN a persisted snapshot with 15,000 records and a source that fails with a transport error
- WHEN a sync runs
- THEN it fails with `.offline`
- AND the catalog still answers queries from the 15,000 cached records

#### Scenario: 503 is retried, 404 is not

- GIVEN a source returning `503` twice then success, and a second source returning `404`
- WHEN a sync runs
- THEN the `503` source was requested three times and succeeded
- AND the `404` source was requested exactly once and reported `.httpStatus(404)`

#### Scenario: Malformed payload preserves the cached catalog

- GIVEN a persisted snapshot and a source returning a body that is not valid JSON
- WHEN a sync runs
- THEN it fails with `.malformedPayload` and the persisted snapshot is unchanged

### Requirement: Tolerant decoding of the published payload shapes

Decoding MUST tolerate the shapes the published API actually emits: a cask `name` that is an array
of strings, a `null` `desc`, a `null` `caveats`, `uses_from_macos` elements that are either a string
or an object, and keys the decoder does not know. Unknown keys MUST be ignored rather than failing.
An individual record that cannot be decoded MUST be skipped without failing the sync, and the number
of skipped records MUST be recorded on the resulting snapshot.

#### Scenario: Cask name array yields a single display name

- GIVEN a cask record whose `name` is `["iTerm2"]`
- WHEN it is decoded
- THEN its display name is `iTerm2`

#### Scenario: Null description and caveats decode as absent

- GIVEN a record with `"desc": null` and `"caveats": null`
- WHEN it is decoded
- THEN its description and caveats are absent, distinct from empty strings

#### Scenario: Mixed uses_from_macos elements decode

- GIVEN a formula whose `uses_from_macos` is `["curl", {"llvm": ["build"]}]`
- WHEN it is decoded
- THEN both elements decode and the record is retained

#### Scenario: Unknown keys are ignored

- GIVEN a record carrying keys the decoder does not model
- WHEN it is decoded
- THEN it decodes successfully and the unknown keys are discarded

#### Scenario: One malformed record does not kill the payload

- GIVEN a payload of 100 records where 3 have a malformed shape
- WHEN it is decoded
- THEN the snapshot contains 97 records and reports 3 skipped records

### Requirement: Slim persisted projection with a state sidecar

A successful sync MUST persist a slim projection containing only the fields the search and detail
capabilities require, plus a state sidecar recording, per source, `schemaVersion`, the validators
(`etag` and/or `lastModified`), `downloadedAt`, and `recordCount`. A sidecar whose `schemaVersion`
does not match the one the running build expects MUST be treated as no cache — the system MUST
re-sync from scratch and MUST NOT fail or crash on it.

#### Scenario: State sidecar round-trips

- GIVEN a completed sync of 7,000 formulae and 8,500 casks
- WHEN the persisted state is read back
- THEN it reports `recordCount` 7,000 and 8,500 for the respective sources, a `downloadedAt`, the
  current `schemaVersion`, and the validators returned by the source

#### Scenario: Unknown schema version is treated as no cache

- GIVEN a persisted sidecar whose `schemaVersion` is greater than the one this build expects
- WHEN the catalog loads
- THEN it reports no usable cache, no error is thrown, and a full sync is scheduled

### Requirement: Freshness policy — 24-hour silent refresh, cache always served

A catalog whose newest `downloadedAt` is older than 24 hours MUST be refreshed in the background
without blocking or clearing results. Cached results MUST be served throughout the refresh and MUST
be replaced only when a sync succeeds. A catalog younger than 24 hours MUST NOT trigger an automatic
network sync. A manual refresh MUST run a sync regardless of age.

#### Scenario: Fresh catalog does not sync on launch

- GIVEN a persisted snapshot downloaded 2 hours ago
- WHEN the catalog loads
- THEN no sync request is issued and the cached records are served

#### Scenario: Stale catalog refreshes silently

- GIVEN a persisted snapshot downloaded 30 hours ago
- WHEN the catalog loads
- THEN a background sync starts, queries keep returning the cached records while it runs
- AND the new records are served only after the sync succeeds

#### Scenario: Manual refresh ignores age

- GIVEN a persisted snapshot downloaded 2 hours ago
- WHEN a manual refresh is requested
- THEN a sync is issued

### Requirement: First run is non-blocking with observable sync progress

With no usable cache, the catalog MUST resolve immediately to an empty result set rather than
blocking, waiting, or throwing. Sync progress MUST be exposed as exactly one case of a closed
`CatalogSyncStatus` enumeration: `idle`, `downloading(fractionCompleted: Double?)`, `decoding`,
`succeeded(at: Date)`, or `failed(CatalogSyncError)`, so a consumer can render it without inspecting
transport internals. Results MUST become available as soon as the first sync succeeds.

#### Scenario: Cold launch answers immediately with empty results

- GIVEN no persisted catalog and a source that has not yet responded
- WHEN a query runs
- THEN it returns zero results without blocking
- AND the status is `downloading` or `decoding`

#### Scenario: Results appear when the first sync lands

- GIVEN the cold-launch state above
- WHEN the sync succeeds with 15,000 records
- THEN the status becomes `succeeded(at:)` and the same query now returns non-zero results

#### Scenario: Failed first sync is observable and non-fatal

- GIVEN no persisted catalog and a source that fails with a transport error
- WHEN the sync completes
- THEN the status is `failed(.offline)`, queries still return zero results, and nothing is thrown

### Requirement: Analytics counts are parsed locale-independently and degrade gracefully

The sync MUST acquire 365-day install-on-request counts for formulae and 365-day install counts for
casks and join them onto the snapshot by `(kind, name)`. Counts arrive as comma-grouped decimal
strings and MUST be parsed locale-independently. A package with no analytics entry MUST carry an
absent count, distinct from a count of zero. Failure to acquire analytics MUST NOT fail the sync:
the snapshot MUST still persist and the catalog MUST remain fully usable with absent counts.

#### Scenario: Comma-grouped counts parse regardless of locale

- GIVEN an analytics entry with `"count": "2,808,879"`
- WHEN it is parsed under a locale that uses `.` as the group separator
- THEN the parsed value is `2808879`

#### Scenario: Analytics failure leaves the catalog usable

- GIVEN a payload sync that succeeds and an analytics fetch that fails
- WHEN the sync completes
- THEN the sync reports success, the snapshot is persisted, and every record has an absent count

#### Scenario: Missing analytics entry is absent, not zero

- GIVEN a successful analytics fetch that contains no entry for formula `obscure`
- WHEN `obscure` is inspected
- THEN its install count is absent and is not `0`

### Requirement: A snapshot is adopted exactly once, in order

The catalog MUST adopt each snapshot at most once, however many ingresses deliver it — cache load,
manual refresh, and the sync event stream. A manual refresh keeps its existing contract: it runs a
sync regardless of catalog age and returns once the resulting snapshot is queryable. When two
adoptions overlap, the catalog MUST end up serving the newer snapshot; an adoption of an older
snapshot that completes later MUST be discarded rather than installed. Cached results MUST remain
queryable for the whole duration of an adoption.

"Newer" MUST be determined by the snapshot's own revision — the order snapshots were materialized —
and MUST NOT be determined by the order in which adoption was called. An older snapshot whose
adoption is called after a newer snapshot has already been installed MUST therefore be discarded on
exactly the same terms as one whose adoption merely finishes late. The record of which revision has
been adopted MUST NOT regress to an older revision, so a snapshot that was discarded MUST NOT
disarm the deduplication of the newer one that is being served.

#### Scenario: A manual refresh adopts its snapshot once

- GIVEN a running catalog that is also observing the sync event stream
- WHEN a manual refresh completes a sync that produces snapshot `S`
- THEN the search index is built exactly once for `S`
- AND the served record count and results are `S`'s

#### Scenario: A late adoption of an older snapshot is discarded

- GIVEN the adoption of snapshot `A` is still in progress when newer snapshot `B` is delivered
- WHEN `B` finishes adopting first and `A`'s adoption completes afterwards
- THEN the catalog still serves `B`
- AND the served record count and results are `B`'s, not `A`'s

#### Scenario: An older snapshot arriving after a newer one has installed is discarded

- GIVEN a catalog already serving snapshot `B`, whose revision is newer than snapshot `A`'s
- WHEN adoption is called for `A` only after `B` has been fully installed
- THEN the catalog still serves `B`'s record count and results, and `A` is never installed
- AND the adopted-revision record still names `B`'s revision, so a re-delivery of `B` is still
  deduplicated

#### Scenario: Results never blank while a snapshot is adopted

- GIVEN a catalog serving 15,000 cached records
- WHEN a new snapshot is adopted
- THEN every query issued while that adoption is in progress returns the previous results
- AND no query observes an empty result set caused by the swap

### Requirement: A single-flight join is satisfied only by work still in flight

Overlapping sync requests MUST be coalesced onto the one run genuinely in flight. A request that
arrives after the run in flight has settled, or after that run was cancelled, MUST start fresh
work: it MUST NOT be answered with the already-settled result, and it MUST NOT be answered with
`cancelled` from the previous attempt. A settled run MUST vacate the coalescing slot before any
joined caller resumes, never afterwards. Cancelling a sync MUST prevent any later request from
joining the cancelled run; the later request starts fresh work, and that fresh work MUST NOT begin
acquisition until the cancelled run has finished unwinding its staging area.

#### Scenario: Concurrent callers coalesce onto one sync

- GIVEN a source that does not answer until it is released
- WHEN two callers request a sync before the source is released
- THEN exactly one acquisition is performed
- AND both callers receive the same result

#### Scenario: A settled sync does not answer a later caller

- GIVEN a sync that has already completed against a source serving payload `P1`
- WHEN a sync is requested afterwards and the source now serves payload `P2`
- THEN a second acquisition is performed
- AND the second caller's result reflects `P2`

#### Scenario: A cancelled sync does not answer a later caller

- GIVEN a sync in flight that is cancelled
- WHEN a sync is requested after that cancellation
- THEN fresh acquisition work starts
- AND the later caller does not receive `cancelled` from the cancelled attempt

### Requirement: A zero-package catalog is never published as success

A sync MUST NOT report success for, publish, or persist a snapshot containing zero packages. Any
sync whose candidate snapshot would contain zero packages MUST fail with `malformedPayload`, MUST
leave the previously persisted snapshot and its state intact and served, and MUST NOT write a
snapshot or a state sidecar for the rejected result. This applies to every path that can produce a
candidate snapshot, including the path where every payload resource revalidates as unchanged while
no readable previous snapshot exists. The threshold is exactly zero packages: the system MUST NOT
apply any other plausibility floor, so a small but non-empty catalog MUST persist normally.

#### Scenario: A degenerate payload from the origin is rejected

- GIVEN a persisted snapshot of 15,000 records and a source returning a well-formed payload that
  yields zero packages
- WHEN a sync runs
- THEN it fails with `malformedPayload`
- AND no snapshot or state sidecar is written
- AND the 15,000 cached records are still served

#### Scenario: An unchanged answer with no readable cache does not succeed empty

- GIVEN no readable persisted snapshot and a source that answers "unchanged" for every payload
  resource
- WHEN a sync runs
- THEN it does not report success and publishes no snapshot
- AND the status is `failed(.malformedPayload)`

#### Scenario: A degenerate first sync stays non-fatal

- GIVEN no persisted catalog and a first sync whose payload yields zero packages
- WHEN the sync completes
- THEN the status is `failed(.malformedPayload)`, queries return zero results, and nothing is thrown
- AND no snapshot file exists on disk afterwards

#### Scenario: A one-package catalog is not degenerate

- GIVEN a source returning a payload that yields exactly one package
- WHEN a sync runs
- THEN it succeeds and the one-package snapshot is persisted and served

### Requirement: A persisted zero-package snapshot is treated as no cache

A persisted snapshot containing zero packages MUST be classified as no usable cache, exactly as a
missing, corrupt or newer-schema file is. Loading it MUST NOT throw, MUST NOT be reported through a
`CatalogSyncStatus` case dedicated to the discarded snapshot, and MUST leave the consumer in the
ordinary cold-launch state. Because no readable snapshot backs the stored validators, the next sync
MUST be unconditional — it MUST NOT replay `If-Modified-Since` or `If-None-Match` — so a machine
carrying a poisoned snapshot recovers on its next sync instead of revalidating into it forever. The
threshold is the same on the read side: a persisted snapshot with at least one package remains a
usable cache.

#### Scenario: A poisoned snapshot on disk is silently ignored

- GIVEN a persisted snapshot file with a current `schemaVersion` containing zero packages, and a
  sidecar recording validators for both sources
- WHEN the catalog loads
- THEN it reports no usable cache, nothing is thrown, and queries return zero results
- AND the status is the ordinary cold-launch progression, not `failed`

#### Scenario: Recovery from a poisoned snapshot is unconditional

- GIVEN the on-disk state above
- WHEN the next sync runs
- THEN the recorded request carried neither `If-Modified-Since` nor `If-None-Match`
- AND a successful response replaces the poisoned snapshot and its records are served

#### Scenario: A one-package persisted snapshot is still a usable cache

- GIVEN a persisted snapshot containing exactly one package
- WHEN the catalog loads
- THEN it reports a usable cache and serves that package

## Provenance

- Established by change `m1-catalog-browse` (archived `2026-08-01`), ADDED-only delta — 9
  requirements / 26 scenarios, copied verbatim from
  `openspec/changes/archive/2026-08-01-m1-catalog-browse/specs/catalog-sync/spec.md`. This is the
  first main spec for the capability; nothing was modified or removed.
- **Implementation evidence for "Slim persisted projection with a state sidecar" (post-verify
  correction, 2026-08-01)**: the native branch review (lineage `review-c71698f49010e184`) found
  finding `R3-revalidated-sync-persists-empty-catalog` — a `304` revalidation whose persisted
  snapshot could not be read persisted an *empty* catalog and reported success, i.e. it treated an
  unreadable cache as an empty valid cache instead of as no cache. Commit `b9077c5` added the
  `acquirePayloads` `revalidatable` flag so a source is only revalidated when a readable snapshot
  backs it, plus a regression test. **The requirement text is unchanged** — the fix implements what
  this requirement already mandated ("MUST be treated as no cache") and what "Conditional
  revalidation without full re-download" requires of an unchanged response ("MUST keep the existing
  snapshot"). Recorded here as implementation evidence only; receipt `terminal_state: approved`,
  `evidence_outcome: passed`.
- **Extended by change `m2-catalog-hardening` (archived `2026-08-02`)**, ADDED-only delta — 4
  requirements / 13 scenarios copied verbatim from
  `openspec/changes/archive/2026-08-02-m2-catalog-hardening/specs/catalog-sync/spec.md` and appended
  after "Analytics counts are parsed locale-independently and degrade gracefully": "A snapshot is
  adopted exactly once, in order", "A single-flight join is satisfied only by work still in flight",
  "A zero-package catalog is never published as success", and "A persisted zero-package snapshot is
  treated as no cache". Nothing was modified, removed or renamed — the 9 M1 requirements and their
  26 scenarios keep their text byte-for-byte. Capability total after the merge: **13 requirements /
  39 scenarios**. These four requirements close M1 follow-ups #2, #3, #6 and #7 (see the M1 archive
  report's follow-up register).
  - The "single-flight join" requirement carries the user-approved **mark-and-drain** cancellation
    wording (Engram `#7070`): `cancel()` marks and cancels the slot, and a successor drains the
    cancelled run before starting fresh work, so the dying run's staging purge cannot delete the
    successor's in-flight download. It replaced the proposal's original "cancelling MUST make the
    slot available immediately".
  - **Implementation note for "A zero-package catalog is never published as success"** (native
    review lineage `review-93ca396315542808`, SUGGESTION, non-blocking): the delivered refusal is
    carried by the `CatalogFileStore.persist` structural guard plus M1's per-resource decoder guard.
    The additional engine-side semantic guard named in the change's design D4 and tasks 4.x was not
    separately implemented. The requirement is satisfied and all four scenarios are COMPLIANT; the
    drift is between the archived design/tasks and the code, not between the spec and the code.
  - **Implementation note for "A persisted zero-package snapshot is treated as no cache"** (same
    review lineage, WARNING, non-blocking): recovery is reached through the existing freshness path,
    so a poisoned snapshot sitting beside a *fresh* sidecar leaves an empty, silent catalog until the
    staleness window passes. The requirement text is unchanged — tightening the trigger is tracked as
    a follow-up, not a spec gap.
- **Amended by change `m3-hardening-prelude` (archived `2026-08-03`, PRD milestone **M3**, slice
  M3-0 — the hardening prelude)**: **1 MODIFIED** requirement replaced as a whole block — "A snapshot
  is adopted exactly once, in order" — adding **1 scenario**. 13 requirements / 39 scenarios →
  **13 requirements / 40 scenarios**. Nothing was added, removed or renamed; the other twelve
  requirements are byte-identical, and the replacement is a strict superset of the text it replaced.
  Previously the requirement ordered adoptions but left "newer" **undefined**, so it was decided by
  the order adoption was *called*: an older snapshot whose adoption began after a newer one had
  already installed replaced it, and overwrote the adopted-revision record with the older revision,
  disarming the deduplication of the snapshot actually being served
  (`CatalogStore.swift:179-183`). This closed **M2-0 #1 / M2-2 #12**, the oldest open defect in the
  project, which three consecutive slices had carried forward.
  - **"Newer" is the snapshot's `revision.ordinal`** — materialization order, already monotonic — and
    deliberately **not** a `fetchedAt` timestamp, so no new state was introduced (settled product
    decision Q5, 2026-08-03, Engram `#7130`).
  - Delivered as a single ordinal guard that makes the `adoptedRevision =` assignment unreachable for
    an older snapshot. `adoptionSequence` / `installedSequence` are **unchanged** — they guard build
    completion, not arrival (design D2) — and an **equal** ordinal keeps the existing
    join-a-duplicate contract byte-for-byte. Pinned by `CatalogAdoptionTests >
    anOlderSnapshotArrivingAfterANewerOneIsDiscarded` and
    `theAdoptedRevisionDoesNotRegressAfterDiscardingAnOlderSnapshot`; the suite also gained
    `.timeLimit(.minutes(1))` (M2-0 #4).
  - **Native review note (lineage `review-fa82e5eaa3023fc4`)**: the reviewer positively verified the
    guard is race-free — `CatalogStore` is `@MainActor` and the check-then-assign sequence contains
    no suspension point.
- The archived delta specs are the verbatim audit trail; this file adds only the header, the
  `## Requirements` wrapper, and this provenance section.
