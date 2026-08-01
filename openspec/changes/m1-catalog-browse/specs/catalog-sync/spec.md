# Delta for catalog-sync

New capability — no existing spec. All requirements are ADDED.

Scope: acquiring, revalidating, decoding, persisting and refreshing the Homebrew catalog
(`homebrew/core` formulae + `homebrew/cask` casks) and its 365-day analytics counts.

## ADDED Requirements

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
