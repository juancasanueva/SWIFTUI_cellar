# Delta for catalog-sync

Existing capability — `openspec/specs/catalog-sync/spec.md` (9 requirements / 26 scenarios).

Delta summary: 4 ADDED requirements / 13 scenarios. Nothing is MODIFIED, REMOVED or RENAMED —
every existing requirement, including "A failed sync never erases the last good catalog", "Slim
persisted projection with a state sidecar" and "Freshness policy — 24-hour silent refresh, cache
always served", keeps its current text and scenarios verbatim. The behaviour added here is
additive: a new classification (zero packages = degenerate) and two invariants (adopt once in
order, join only work in flight) that the existing requirements never stated.

Binding product decisions (user-confirmed 2026-08-02, Engram `sdd/m2-catalog-hardening/proposal-decisions`):
Q1 discarded poisoned snapshot is silent, no new `CatalogSyncStatus` case; Q2 a degenerate payload
from the origin is a visible `failed(.malformedPayload)` that keeps the last good catalog; Q3 the
degeneracy threshold is zero packages only, with no plausibility floor; Q4 `refreshNow()` keeps its
contract and its ingress, de-duplicated by snapshot identity.

Not specified here: the shared `CellarTestSupport` target and the cancellation-aware `TestClock`
(proposal defect #10). They change no product behaviour a consumer can observe — they are test
infrastructure that makes the scenarios below automatable without wall-clock sleeps. They belong to
design and tasks, not to a requirement. The product-visible half of cancellation is already
specified: `cancelled` is a case of the closed `CatalogSyncError` enumeration.

## ADDED Requirements

### Requirement: A snapshot is adopted exactly once, in order

The catalog MUST adopt each snapshot at most once, however many ingresses deliver it — cache load,
manual refresh, and the sync event stream. A manual refresh keeps its existing contract: it runs a
sync regardless of catalog age and returns once the resulting snapshot is queryable. When two
adoptions overlap, the catalog MUST end up serving the newer snapshot; an adoption of an older
snapshot that completes later MUST be discarded rather than installed. Cached results MUST remain
queryable for the whole duration of an adoption.

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
